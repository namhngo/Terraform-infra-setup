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

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used by IRSA trust policies)"
  value       = module.eks.cluster_oidc_issuer_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "loki_iam_role_arn" {
  description = "IRSA role ARN for the Loki ServiceAccount"
  value       = aws_iam_role.loki.arn
}

output "tempo_iam_role_arn" {
  description = "IRSA role ARN for the Tempo ServiceAccount"
  value       = aws_iam_role.tempo.arn
}

output "alloy_iam_role_arn" {
  description = "IRSA role ARN for the Alloy ServiceAccount"
  value       = aws_iam_role.alloy.arn
}

output "grafana_iam_role_arn" {
  description = "IRSA role ARN for the Grafana ServiceAccount"
  value       = aws_iam_role.grafana.arn
}

output "lb_controller_iam_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  value       = module.lb_controller_irsa.iam_role_arn
}
