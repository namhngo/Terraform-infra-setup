variable "project_name" {
  description = "Short lowercase name used in resource names and tags."
  type        = string
  default     = "static-site"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 4-32 characters, lowercase, and use only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment label applied to managed resources."
  type        = string
  default     = "learning"

  validation {
    condition     = trimspace(var.environment) != ""
    error_message = "environment must not be empty."
  }
}

variable "aws_region" {
  description = "AWS region for the S3 bucket and Route 53 data lookups."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid-looking AWS region name."
  }
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name. Leave null to let AWS generate one from bucket_prefix."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.bucket_name == null || (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("\\.\\.", var.bucket_name)) &&
      !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid S3 bucket name when provided."
  }
}

variable "domain_name" {
  description = "Optional fully qualified custom domain for the CloudFront distribution."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.domain_name == null || (
      trimspace(var.domain_name) != "" &&
      can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", lower(var.domain_name)))
    )
    error_message = "domain_name must be a fully qualified DNS name when provided."
  }
}

variable "route53_zone_name" {
  description = "Route 53 hosted zone name used for ACM validation and the alias record."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.route53_zone_name == null || (
      trimspace(var.route53_zone_name) != "" &&
      can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", lower(trim(var.route53_zone_name, "."))))
    )
    error_message = "route53_zone_name must be a hosted-zone DNS name when provided."
  }
}

variable "create_dns_records" {
  description = "Request and validate an ACM certificate, then create Route 53 alias and validation records."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow Terraform to delete all bucket objects during destroy. Keep false for safer cleanup."
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for edge locations."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "tags" {
  description = "Additional tags merged with the project's default tags."
  type        = map(string)
  default     = {}
}
