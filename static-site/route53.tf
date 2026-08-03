data "aws_route53_zone" "site" {
  count = local.dns_records_enabled ? 1 : 0

  name         = "${trim(var.route53_zone_name == null ? "" : var.route53_zone_name, ".")}."
  private_zone = false
}

resource "aws_route53_record" "site_ipv4" {
  count = local.dns_records_enabled ? 1 : 0

  name    = var.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.site[0].zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
  }
}

resource "aws_route53_record" "site_ipv6" {
  count = local.dns_records_enabled ? 1 : 0

  name    = var.domain_name
  type    = "AAAA"
  zone_id = data.aws_route53_zone.site[0].zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
  }
}
