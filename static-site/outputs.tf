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

output "bucket_name" {
  description = "Name of the private S3 origin bucket."
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "ARN of the private S3 origin bucket."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used for invalidations."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront-generated hostname."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "HTTPS URL for the deployed site."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}
