resource "aws_acm_certificate" "site" {
  count = local.custom_domain_enabled ? 1 : 0

  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  count = local.dns_records_enabled ? 1 : 0

  allow_overwrite = true
  name            = one(aws_acm_certificate.site[0].domain_validation_options).resource_record_name
  records         = [one(aws_acm_certificate.site[0].domain_validation_options).resource_record_value]
  ttl             = 60
  type            = one(aws_acm_certificate.site[0].domain_validation_options).resource_record_type
  zone_id         = data.aws_route53_zone.site[0].zone_id
}

resource "aws_acm_certificate_validation" "site" {
  count = local.dns_records_enabled ? 1 : 0

  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [aws_route53_record.acm_validation[0].fqdn]

  timeouts {
    create = "30m"
  }
}
