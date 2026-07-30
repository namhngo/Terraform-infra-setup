# Outputs are added incrementally as each resource type is implemented.

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALBs)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Fargate tasks)"
  value       = module.vpc.private_subnets
}

output "loki_bucket" {
  description = "S3 bucket for Loki chunks"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket" {
  description = "S3 bucket for Tempo blocks"
  value       = aws_s3_bucket.tempo.id
}

output "alloy_bearer_token_secret_arn" {
  description = "Secrets Manager ARN for the Alloy bearer token"
  value       = aws_secretsmanager_secret.alloy_bearer_token.arn
}

output "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for the Grafana admin password"
  value       = aws_secretsmanager_secret.grafana_admin_password.arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name"
  value       = { for k, r in aws_ecr_repository.images : k => r.repository_url }
}
