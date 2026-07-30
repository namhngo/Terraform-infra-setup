# TLS certificate for the public ALB. Optional: set domain_name and
# route53_zone_id to serve the stack over HTTPS. Without a domain there's no
# way to obtain a publicly trusted certificate, so the stack falls back to
# plaintext HTTP — a genuine exposure (the Grafana password and telemetry
# payloads cross the internet in the clear) and the default, so
# var.domain_name's description spells out the consequence.
#
# Unlike observability-eks (where the ALB is created by an in-cluster
# controller the platform stack can't see, forcing the DNS alias record into
# a second stack), this is one root module: the ALB's DNS name is known right
# after aws_lb.public is created, so the whole TLS + DNS chain lives in this
# one file.

locals {
  enable_tls = var.domain_name != ""
  fqdn       = local.enable_tls ? "${var.subdomain}.${var.domain_name}" : ""
}

resource "aws_acm_certificate" "public" {
  count = local.enable_tls ? 1 : 0

  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.enable_tls ? {
    for opt in aws_acm_certificate.public[0].domain_validation_options :
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

resource "aws_acm_certificate_validation" "public" {
  count = local.enable_tls ? 1 : 0

  certificate_arn         = aws_acm_certificate.public[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "public_alb" {
  count = local.enable_tls ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = true
  }
}
