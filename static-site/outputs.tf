output "custom_domain_enabled" {
  description = "Whether the distribution is configured with a custom domain."
  value       = local.custom_domain_enabled
}

output "project_name" {
  description = "Project name used for resource naming and tags."
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region configured for the S3 origin."
  value       = var.aws_region
}
