# Points the hostname at the ALB. Only created when the platform stack issued a
# certificate; without a domain there is nothing to alias.
#
# The record lives in this stack rather than alongside the certificate because
# the ALB is created by the in-cluster controller in response to the Ingresses
# above, so its DNS name is not knowable until they exist.

# depends_on defers this read until apply, since the ALB does not exist at plan
# time on a first run. The tags are the ones the controller stamps on the ALB it
# creates for an ingress group.
data "aws_lb" "observability" {
  count = local.enable_tls ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = data.aws_eks_cluster.this.name
    "ingress.k8s.aws/stack" = local.platform.project_name
  }

  depends_on = [
    kubernetes_ingress_v1.alloy,
    kubernetes_ingress_v1.grafana,
  ]
}

resource "aws_route53_record" "observability" {
  count = local.enable_tls ? 1 : 0

  zone_id = local.platform.route53_zone_id
  name    = local.platform.hostname
  type    = "A"

  alias {
    name                   = data.aws_lb.observability[0].dns_name
    zone_id                = data.aws_lb.observability[0].zone_id
    evaluate_target_health = true
  }
}
