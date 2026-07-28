output "state_bucket" {
  description = "Name of the S3 bucket holding remote state; pass to other stacks as -backend-config=bucket=<name>"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket"
  value       = aws_s3_bucket.state.arn
}
