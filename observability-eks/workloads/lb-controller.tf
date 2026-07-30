# AWS Load Balancer Controller — watches Ingress resources and provisions the
# ALB. Runs in kube-system, not the monitoring namespace, since it is a
# cluster-wide controller rather than an observability component.
#
# It owns AWS resources that are not in any Terraform state: the ALB, its target
# groups and its listeners. That is normal and is how ingress works on EKS — pods
# reschedule continuously, so only an in-cluster controller can keep target
# registrations current. It does mean the controller must outlive the ingresses
# during a teardown, which is exactly what the stack split guarantees.
#
# The IRSA role is created in the platform stack; only the release lives here.

resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = local.role_arns.lb_controller
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
    value = data.aws_eks_cluster.this.name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = local.platform.vpc_id
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
  # group for ALB-to-pod traffic and attaches it to the node group ENIs, which
  # makes it undeletable until the nodes are gone — and Terraform never knew it
  # existed, so nothing removed it and it blocked the VPC delete. Disabling it
  # makes the controller add its rules to the node security group instead, which
  # the platform stack owns and destroys normally.
  set {
    name  = "enableBackendSecurityGroup"
    value = "false"
  }

  depends_on = [kubernetes_service_account.lb_controller]
}
