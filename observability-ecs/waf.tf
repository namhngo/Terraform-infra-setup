# WAF Web ACL — attached to the PUBLIC ALB only (see alb-public.tf). The
# internal ALB (alb-internal.tf) has no WAF: its security group is the entire
# trust boundary for that path, since it's unreachable from the internet by
# design.

resource "aws_wafv2_web_acl" "observability" {
  name  = "${var.project_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Authentication for the public ingest path (/v1/*).
  #
  # Alloy's OTLP receivers do not validate credentials, and an ALB has no
  # native bearer-token support, so this WAF rule is the enforcement point:
  # requests under /v1/ are blocked unless they carry exactly the expected
  # Authorization header. Grafana's paths are untouched — it has its own
  # login. The internal ALB needs no equivalent rule: its ingest path never
  # reaches the internet, so the security group allowlist already is the
  # authentication.
  #
  # Priority 0 so unauthenticated traffic is rejected before it consumes any
  # of the rate-limit or managed-rule budget below.
  rule {
    name     = "require-bearer-token-on-ingest"
    priority = 0

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "STARTS_WITH"
            search_string         = "/v1/"

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  single_header {
                    name = "authorization"
                  }
                }
                positional_constraint = "EXACTLY"
                search_string         = "Bearer ${random_password.alloy_bearer_token.result}"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RequireBearerToken"
      sampled_requests_enabled   = false # would log the token itself
    }
  }

  rule {
    name     = "aws-managed-common-rule-set"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "size-restriction-1mb"
    priority = 2

    action {
      block {}
    }

    statement {
      size_constraint_statement {
        field_to_match {
          body {}
        }
        comparison_operator = "GT"
        size                = 1048576 # 1 MB — legitimate OTLP batches are typically < 100 KB

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SizeRestriction"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit-1000-per-5min"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "public_alb" {
  resource_arn = aws_lb.public.arn
  web_acl_arn  = aws_wafv2_web_acl.observability.arn
}
