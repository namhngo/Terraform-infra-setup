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

output "ecs_task_execution_role_arn" {
  description = "Shared ECS task execution role ARN (ECR pull, CloudWatch Logs)"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "task_role_arns" {
  description = "Per-service ECS task role ARNs (app-level AWS permissions)"
  value       = { for k, r in aws_iam_role.task : k => r.arn }
}

output "security_group_ids" {
  description = "Security group IDs keyed by name"
  value = {
    alb_public   = aws_security_group.alb_public.id
    alb_internal = aws_security_group.alb_internal.id
    alloy        = aws_security_group.alloy.id
    loki         = aws_security_group.loki.id
    tempo        = aws_security_group.tempo.id
    prometheus   = aws_security_group.prometheus.id
    grafana      = aws_security_group.grafana.id
  }
}

output "public_endpoint" {
  description = "Public ALB endpoint (Grafana at /, telemetry ingest at /v1/*)"
  value       = local.enable_tls ? "https://${local.fqdn}" : "http://${aws_lb.public.dns_name}"
}

output "public_alb_dns_name" {
  description = "Public ALB's raw DNS name (always available, regardless of domain_name)"
  value       = aws_lb.public.dns_name
}
