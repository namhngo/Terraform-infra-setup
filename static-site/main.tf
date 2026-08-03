terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.default_tags
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}

locals {
  default_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  )

  custom_domain_enabled  = var.domain_name != null && trimspace(var.domain_name) != ""
  dns_records_enabled    = local.custom_domain_enabled && var.create_dns_records
  configured_bucket_name = var.bucket_name == null ? "" : trimspace(var.bucket_name)
  normalized_domain_name = trim(var.domain_name == null ? "" : var.domain_name, ".")
  normalized_zone_name   = trim(var.route53_zone_name == null ? "" : var.route53_zone_name, ".")
}

resource "terraform_data" "configuration" {
  input = {
    bucket_name        = local.configured_bucket_name
    create_dns_records = var.create_dns_records
    domain_name        = var.domain_name
    route53_zone_name  = var.route53_zone_name
  }

  lifecycle {
    precondition {
      condition     = !var.create_dns_records || local.custom_domain_enabled
      error_message = "create_dns_records requires a non-empty domain_name."
    }

    precondition {
      condition     = !var.create_dns_records || (var.route53_zone_name != null && trimspace(var.route53_zone_name) != "")
      error_message = "create_dns_records requires route53_zone_name."
    }

    precondition {
      condition     = !local.custom_domain_enabled || var.create_dns_records
      error_message = "domain_name requires create_dns_records = true so ACM validation can complete automatically."
    }

    precondition {
      condition = !var.create_dns_records || endswith(
        "${lower(local.normalized_domain_name)}.",
        "${lower(local.normalized_zone_name)}."
      )
      error_message = "domain_name must be equal to or below route53_zone_name."
    }
  }
}
