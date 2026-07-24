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

output "alloy_bearer_token_secret_arn" {
  description = "Secrets Manager ARN for the Alloy bearer token (retrieve value via aws secretsmanager get-secret-value)"
  value       = aws_secretsmanager_secret.alloy_bearer_token.arn
}

output "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for the Grafana admin password"
  value       = aws_secretsmanager_secret.grafana_admin_password.arn
}
