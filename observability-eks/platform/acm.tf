# TLS certificate for the ALB. Optional: set domain_name and route53_zone_id to
# serve the stack over HTTPS.
#
# Without a domain there is no way to obtain a publicly trusted certificate, so
# the stack falls back to plaintext HTTP. That is a genuine exposure — the Grafana
# admin password and every telemetry payload cross the internet in the clear — and
# it is the default, so var.domain_name documents the consequence and
# var.route53_zone_id has a validation rule requiring the two be set together.

locals {
  enable_tls = var.domain_name != ""

  # One hostname serves the whole stack; the Ingresses split it by path, sending
  # /v1/* to Alloy and everything else to Grafana.
  fqdn = local.enable_tls ? "${var.subdomain}.${var.domain_name}" : ""
}

resource "aws_acm_certificate" "observability" {
  count = local.enable_tls ? 1 : 0

  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records. The certificate is not usable until these resolve, so
# the validation resource below blocks until AWS confirms them.
resource "aws_route53_record" "cert_validation" {
  for_each = local.enable_tls ? {
    for opt in aws_acm_certificate.observability[0].domain_validation_options :
    opt.domain_name => {
      name   = opt.resource_record_name
      record = opt.resource_record_value
      type   = opt.resource_record_type
    }
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "observability" {
  count = local.enable_tls ? 1 : 0

  certificate_arn         = aws_acm_certificate.observability[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# Alias record pointing the hostname at the ALB. The ALB is created by the
# in-cluster load balancer controller, so its DNS name is not known to this
# stack — the record is created by the workloads stack instead, which can look
# the ALB up once the ingress exists.
