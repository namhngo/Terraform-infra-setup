# AWS Load Balancer Controller — watches Ingress resources and
# auto-provisions ALBs. Runs in kube-system, not the monitoring namespace,
# since it's a cluster-wide controller, not an observability component.

# IRSA role using the official AWS-published policy via the community
# submodule — that policy has ~20 statements and changes with new ALB
# features, not worth hand-maintaining like the simpler roles in iam.tf.
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-lb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
    }
  }
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lb_controller.metadata[0].name
  }

  # By default the controller creates a shared "k8s-traffic-<cluster>" security
  # group for ALB-to-pod traffic. It is attached to the node group ENIs, so it
  # cannot be deleted until the node group is gone — which is after the
  # pre-destroy hook runs — and Terraform never knew about it, so nothing else
  # removes it either. The result is an orphaned group that blocks the VPC
  # delete. Disabling it makes the controller add its rules to the existing node
  # security group instead, which Terraform owns and destroys normally.
  set {
    name  = "enableBackendSecurityGroup"
    value = "false"
  }

  depends_on = [kubernetes_service_account.lb_controller]
}
