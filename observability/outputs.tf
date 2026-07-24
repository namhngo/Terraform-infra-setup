# Outputs are added incrementally as each resource type is implemented.
# See secrets.tf, iam.tf, main.tf (EKS), kubernetes.tf for their
# respective outputs added in later steps.

output "loki_bucket_name" {
  description = "S3 bucket name for Loki log chunks"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket_name" {
  description = "S3 bucket name for Tempo trace blocks"
  value       = aws_s3_bucket.tempo.id
}
