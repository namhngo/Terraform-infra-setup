resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-oac"
  description                       = "SigV4 access from CloudFront to the private static-site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "assets" {
  name        = "${var.project_name}-assets"
  comment     = "Long-lived cache for immutable static assets"
  default_ttl = 31536000
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_cache_policy" "no_cache" {
  name        = "${var.project_name}-no-cache"
  comment     = "Always revalidate the HTML application shell"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
  }
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.project_name}-security-headers"
  comment = "Baseline security headers for the static site"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = false
    }
  }
}

data "aws_iam_policy_document" "site_origin" {
  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site_origin" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_origin.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.project_name} static site"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  aliases             = local.custom_domain_enabled ? [var.domain_name] : []

  depends_on = [aws_acm_certificate_validation.site]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
    origin_id                = "${var.project_name}-s3"
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = aws_cloudfront_cache_policy.assets.id
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    target_origin_id           = "${var.project_name}-s3"
    viewer_protocol_policy     = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern               = "/index.html"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = aws_cloudfront_cache_policy.no_cache.id
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    target_origin_id           = "${var.project_name}-s3"
    viewer_protocol_policy     = "redirect-to-https"
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = 0
    response_code         = 200
    response_page_path    = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = local.custom_domain_enabled ? aws_acm_certificate.site[0].arn : null
    cloudfront_default_certificate = !local.custom_domain_enabled
    minimum_protocol_version       = local.custom_domain_enabled ? "TLSv1.2_2021" : null
    ssl_support_method             = local.custom_domain_enabled ? "sni-only" : null
  }
}
