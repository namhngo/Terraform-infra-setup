#!/usr/bin/env bash
#
# Deletes the resources owned by the AWS Load Balancer Controller before
# Terraform starts tearing down the cluster. See cleanup.tf for how this is
# wired into the destroy graph.
#
# The controller runs inside the cluster but owns AWS resources (ALB, target
# groups, security groups). If the node group dies before the controller
# finishes deleting them, the ingress finalizers never clear and the leftover
# ALB keeps ENIs in the public subnets, which blocks the subnet, IGW and VPC
# deletes indefinitely.
#
# Every step is best-effort and the script always exits 0: a destroy-time
# provisioner that fails leaves the resource in state and blocks the destroy,
# which would be worse than an incomplete sweep.

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-monitoring}"
VPC_ID="${VPC_ID:-}"

# Own kubeconfig so we never touch the caller's current-context.
KUBECONFIG="$(mktemp -t obs-cleanup-kubeconfig.XXXXXX)"
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT

log() { printf '[pre-destroy] %s\n' "$*"; }

# --- Escalation: drop the controller's admission webhooks and strip finalizers.
# Used when the graceful delete stalls, which means the controller is already
# unreachable. Its webhooks reject every ingress write while its Service has no
# endpoints, so they have to go first or the finalizer patch is rejected too.
force_release_finalizers() {
  log "graceful delete stalled - removing admission webhooks and finalizers"

  kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found >/dev/null 2>&1
  kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found >/dev/null 2>&1

  local kind
  for kind in ingress targetgroupbinding.elbv2.k8s.aws; do
    local name
    while read -r name; do
      [ -n "$name" ] || continue
      log "clearing finalizers on $name"
      kubectl patch "$name" -n "$NAMESPACE" --type=merge \
        -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1
    done < <(kubectl get "$kind" -n "$NAMESPACE" -o name 2>/dev/null)
  done
}

# --- Phase 1: in-cluster deletes, while the controller can still act on them.
cleanup_kubernetes() {
  if [ -z "$CLUSTER_NAME" ]; then
    log "no cluster name provided - skipping in-cluster cleanup"
    return
  fi

  if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "cluster $CLUSTER_NAME is already gone - skipping in-cluster cleanup"
    return
  fi

  if ! aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "could not build a kubeconfig for $CLUSTER_NAME - skipping in-cluster cleanup"
    return
  fi

  log "deleting ingresses in namespace $NAMESPACE"
  if ! kubectl delete ingress --all -n "$NAMESPACE" --ignore-not-found --timeout=180s; then
    force_release_finalizers
    kubectl delete ingress --all -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1
  fi

  log "deleting leftover TargetGroupBindings"
  if ! kubectl delete targetgroupbinding.elbv2.k8s.aws --all -n "$NAMESPACE" \
    --ignore-not-found --timeout=120s; then
    force_release_finalizers
    kubectl delete targetgroupbinding.elbv2.k8s.aws --all -n "$NAMESPACE" \
      --ignore-not-found --wait=false >/dev/null 2>&1
  fi
}

# --- Phase 2: verify AWS-side, and finish the job if the controller could not.
albs_in_vpc() {
  aws elbv2 describe-load-balancers --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text 2>/dev/null
}

cleanup_load_balancers() {
  local arns
  arns="$(albs_in_vpc)"
  [ -n "$arns" ] || return 0

  local arn
  for arn in $arns; do
    log "deleting orphaned load balancer $arn"
    aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$arn" >/dev/null 2>&1
  done

  # ENIs are only released once the ALB is fully deleted.
  local waited=0
  while [ -n "$(albs_in_vpc)" ] && [ "$waited" -lt 180 ]; do
    sleep 10
    waited=$((waited + 10))
  done
  log "load balancers cleared after ${waited}s"
}

cleanup_target_groups() {
  local arns arn
  arns="$(aws elbv2 describe-target-groups --region "$AWS_REGION" \
    --query "TargetGroups[?VpcId=='${VPC_ID}'].TargetGroupArn" \
    --output text 2>/dev/null)"
  [ -n "$arns" ] || return 0

  for arn in $arns; do
    log "deleting orphaned target group $arn"
    aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$arn" >/dev/null 2>&1
  done
}

# Unattached ENIs are pure deletion blockers for the subnets.
cleanup_orphan_enis() {
  local enis eni
  enis="$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null)"
  [ -n "$enis" ] || return 0

  for eni in $enis; do
    log "deleting unattached ENI $eni"
    aws ec2 delete-network-interface --region "$AWS_REGION" --network-interface-id "$eni" >/dev/null 2>&1
  done
}

# The controller creates its own k8s-* security groups. They are invisible to
# Terraform, so nothing else will ever remove them, and the VPC delete blocks
# on them. Retried because the backend SG's rules reference the frontend SG.
cleanup_controller_security_groups() {
  local attempt
  for attempt in 1 2 3; do
    local sgs sg
    sgs="$(aws ec2 describe-security-groups --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=k8s-*" \
      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)"
    [ -n "$sgs" ] || return 0

    for sg in $sgs; do
      log "deleting controller-owned security group $sg (attempt $attempt)"
      aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$sg" >/dev/null 2>&1
    done
    sleep 5
  done
}

cleanup_aws() {
  if [ -z "$VPC_ID" ]; then
    log "no VPC id provided - skipping AWS sweep"
    return
  fi

  cleanup_load_balancers
  cleanup_target_groups
  cleanup_orphan_enis
  cleanup_controller_security_groups
}

log "starting cleanup for cluster=${CLUSTER_NAME:-<none>} vpc=${VPC_ID:-<none>}"
cleanup_kubernetes
cleanup_aws
log "cleanup finished"

exit 0
