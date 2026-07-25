# WAF Web ACL — attached to the shared ALB via the Alloy Ingress annotation
# (the ACL binds at the ALB level, not per-Ingress, so it only needs to be
# referenced once — see ingress.tf).

resource "aws_wafv2_web_acl" "observability" {
  name  = "${var.project_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
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
