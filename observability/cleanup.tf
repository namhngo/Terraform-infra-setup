# Ordering guard for `terraform destroy`.
#
# The AWS Load Balancer Controller runs inside the cluster but owns AWS
# resources (ALB, target groups, security groups). The ingresses depend on
# helm_release.lb_controller, which depends on module.eks.cluster_name — that
# resolves to the EKS *cluster*, not the node group. Terraform therefore sees no
# ordering constraint between the ingresses and the node group and destroys them
# concurrently. When the node group wins that race the controller pods die
# mid-teardown, the ingress finalizers never clear, and the surviving ALB holds
# ENIs in the public subnets, which blocks the subnet, IGW and VPC deletes.
#
# depends_on below is what supplies the missing edge: because destroy order is
# the reverse of create order, this resource is destroyed *before* everything it
# depends on, so the provisioner gets to delete the ingresses while the
# controller is still running. module.eks is the load-bearing entry — it keeps
# the node group alive until the cleanup returns.
resource "null_resource" "pre_destroy_cleanup" {
  # Destroy-time provisioners can only read `self`, so anything the script needs
  # has to be captured here first.
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = var.aws_region
    namespace    = var.k8s_namespace
    vpc_id       = module.vpc.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/pre-destroy-cleanup.sh"

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      AWS_REGION   = self.triggers.region
      NAMESPACE    = self.triggers.namespace
      VPC_ID       = self.triggers.vpc_id
    }
  }

  # module.eks keeps the node group — and therefore the controller — alive until
  # the script returns. module.vpc is listed explicitly because the public
  # subnets are only ever referenced by the controller's subnet auto-discovery
  # tags, so Terraform sees no edge to them and would otherwise try to delete
  # them while the ALB still holds ENIs there.
  depends_on = [
    module.eks,
    module.vpc,
    helm_release.lb_controller,
    kubernetes_ingress_v1.alloy,
    kubernetes_ingress_v1.grafana,
  ]
}
