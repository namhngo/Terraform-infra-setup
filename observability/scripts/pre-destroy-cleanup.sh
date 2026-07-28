#!/usr/bin/env bash
#
# Rescue hook for `terraform destroy`. See cleanup.tf for how it is wired into
# the destroy graph.
#
# The AWS Load Balancer Controller runs inside the cluster but owns AWS
# resources (ALB, target groups, its own k8s-* security groups) that are not in
# Terraform state. Terraform deletes an ingress by removing the object; the
# controller notices, tears down the ALB, and only then clears its finalizer.
# That handshake needs the controller alive, which cleanup.tf guarantees by
# keeping the node group up until this script returns.
#
# So on a healthy teardown this script does nothing. It exists for the case
# where the controller is already broken — a failed apply, a manually scaled
# node group — because then the finalizer can never clear and the destroy
# deadlocks: the ingress delete hangs forever, the surviving ALB pins ENIs into
# the public subnets, and the subnet, IGW and VPC deletes all block behind it.
#
# It deliberately never deletes anything Terraform owns. The kubernetes provider
# treats a missing object as an error rather than success, so deleting an ingress
# here would swap the deadlock for "Failed to delete Ingress ... not found" and
# abort the destroy just as hard. Clearing the finalizer is enough: the object
# stays, and Terraform's own delete then succeeds immediately.
#
# Every step is best-effort and the script always exits 0 — a destroy-time
# provisioner that fails leaves the resource in state and blocks the destroy,
# which is worse than an incomplete sweep. Anything missed is picked up by
# re-running the destroy, since by then the controller is gone and this script
# takes the escalated path.

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-monitoring}"
VPC_ID="${VPC_ID:-}"

# Set when the controller cannot be trusted to clean up after itself, which is
# what makes the AWS-side sweep necessary.
ESCALATED=0

# Own kubeconfig so we never touch the caller's current-context.
KUBECONFIG="$(mktemp -t obs-cleanup-kubeconfig.XXXXXX)"
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT

log() { printf '[pre-destroy] %s\n' "$*"; }

controller_is_ready() {
  local ready
  ready="$(kubectl -n kube-system get deployment aws-load-balancer-controller \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  [ -n "$ready" ] && [ "$ready" -gt 0 ] 2>/dev/null
}

# The controller's admission webhooks reject every ingress write while its
# Service has no endpoints, including the finalizer patch below, so they have to
# go first.
drop_admission_webhooks() {
  kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook \
    --ignore-not-found >/dev/null 2>&1
  kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook \
    --ignore-not-found >/dev/null 2>&1
}

# Ingresses are Terraform-managed: clear the finalizer only and let Terraform
# perform the delete itself.
release_ingress_finalizers() {
  local name
  while read -r name; do
    [ -n "$name" ] || continue
    log "clearing finalizer on $name"
    kubectl patch "$name" -n "$NAMESPACE" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1
  done < <(kubectl get ingress -n "$NAMESPACE" -o name 2>/dev/null)
}

# TargetGroupBindings are created by the controller, not Terraform, so nothing
# else will ever remove them and they keep the namespace in Terminating.
remove_target_group_bindings() {
  local name
  while read -r name; do
    [ -n "$name" ] || continue
    log "removing $name"
    kubectl patch "$name" -n "$NAMESPACE" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1
    kubectl delete "$name" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1
  done < <(kubectl get targetgroupbinding.elbv2.k8s.aws -n "$NAMESPACE" -o name 2>/dev/null)
}

cleanup_kubernetes() {
  if [ -z "$CLUSTER_NAME" ]; then
    log "no cluster name provided - assuming the worst and sweeping AWS"
    ESCALATED=1
    return
  fi

  if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "cluster $CLUSTER_NAME is already gone - sweeping AWS for leftovers"
    ESCALATED=1
    return
  fi

  if ! aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "could not build a kubeconfig for $CLUSTER_NAME - sweeping AWS for leftovers"
    ESCALATED=1
    return
  fi

  if controller_is_ready; then
    log "load balancer controller is ready - leaving the ingress deletes to Terraform"
    return
  fi

  log "load balancer controller is not ready - clearing finalizers so the destroy can proceed"
  ESCALATED=1
  drop_admission_webhooks
  release_ingress_finalizers
  remove_target_group_bindings
}

albs_in_vpc() {
  aws elbv2 describe-load-balancers --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text 2>/dev/null
}

remove_load_balancers() {
  local arns arn
  arns="$(albs_in_vpc)"
  [ -n "$arns" ] || return 0

  for arn in $arns; do
    log "deleting abandoned load balancer $arn"
    aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$arn" >/dev/null 2>&1
  done

  # ENIs are only released once the ALB is fully deleted, and the subnet deletes
  # block until then.
  local waited=0
  while [ -n "$(albs_in_vpc)" ] && [ "$waited" -lt 300 ]; do
    sleep 10
    waited=$((waited + 10))
  done
  log "load balancers cleared after ${waited}s"
}

remove_target_groups() {
  local arns arn
  arns="$(aws elbv2 describe-target-groups --region "$AWS_REGION" \
    --query "TargetGroups[?VpcId=='${VPC_ID}'].TargetGroupArn" \
    --output text 2>/dev/null)"
  [ -n "$arns" ] || return 0

  for arn in $arns; do
    log "deleting abandoned target group $arn"
    aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$arn" >/dev/null 2>&1
  done
}

# Unattached ENIs are pure deletion blockers for the subnets, so this is always
# safe to run.
remove_orphan_enis() {
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

# The controller's own k8s-* security groups are invisible to Terraform and
# block the VPC delete. Attempted unconditionally: AWS refuses to delete one
# that is still in use, so on a healthy teardown these calls simply no-op and
# the controller removes them itself. Retried because the backend group's rules
# reference the frontend group.
remove_controller_security_groups() {
  local attempt sgs sg
  for attempt in 1 2 3; do
    sgs="$(aws ec2 describe-security-groups --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=k8s-*" \
      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)"
    [ -n "$sgs" ] || return 0

    for sg in $sgs; do
      if aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$sg" >/dev/null 2>&1; then
        log "deleted controller-owned security group $sg"
      fi
    done
    sleep 5
  done
}

cleanup_aws() {
  if [ -z "$VPC_ID" ]; then
    log "no VPC id provided - skipping AWS sweep"
    return
  fi

  if [ "$ESCALATED" -eq 1 ]; then
    remove_load_balancers
    remove_target_groups
  fi

  remove_orphan_enis
  remove_controller_security_groups
}

log "starting cleanup for cluster=${CLUSTER_NAME:-<none>} vpc=${VPC_ID:-<none>}"
cleanup_kubernetes
cleanup_aws
log "cleanup finished"

exit 0
