# These outputs are the interface between this stack and ../workloads. Treat
# them as a contract: renaming one breaks the other stack's plan.

# --- Cluster (used by the workloads stack to configure its providers) ---

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

# --- Networking ---

output "vpc_id" {
  description = "VPC hosting the cluster and the ALB"
  value       = module.vpc.vpc_id
}

output "aws_region" {
  description = "Region everything is deployed in"
  value       = var.aws_region
}

# --- Naming / shared settings ---

output "project_name" {
  description = "Resource name prefix, also used as the ALB ingress group name"
  value       = var.project_name
}

output "k8s_namespace" {
  description = "Namespace the observability workloads run in"
  value       = var.k8s_namespace
}

# --- Storage ---

output "loki_bucket" {
  description = "S3 bucket for Loki chunks"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket" {
  description = "S3 bucket for Tempo blocks"
  value       = aws_s3_bucket.tempo.id
}

output "loki_retention_hours" {
  description = "Loki retention, in hours, matching the bucket lifecycle rule"
  value       = var.loki_retention_days * 24
}

output "tempo_retention_hours" {
  description = "Tempo retention, in hours, matching the bucket lifecycle rule"
  value       = var.tempo_retention_days * 24
}

# --- IAM roles for IRSA service account annotations ---

output "iam_role_arns" {
  description = "IRSA role ARNs keyed by ServiceAccount name"
  value = {
    loki          = aws_iam_role.irsa["loki"].arn
    tempo         = aws_iam_role.irsa["tempo"].arn
    alloy         = aws_iam_role.irsa["alloy"].arn
    grafana       = aws_iam_role.irsa["grafana"].arn
    lb_controller = module.lb_controller_irsa.iam_role_arn
  }
}

# --- Secrets ---
# ARNs only. The workloads stack reads the values through a data source so they
# are not duplicated into a second state file.

output "alloy_bearer_token_secret_arn" {
  description = "Secrets Manager ARN for the Alloy ingest bearer token"
  value       = aws_secretsmanager_secret.alloy_bearer_token.arn
}

output "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for the Grafana admin password"
  value       = aws_secretsmanager_secret.grafana_admin_password.arn
}

# --- Edge ---

output "waf_web_acl_arn" {
  description = "WAF ACL to attach to the ALB via ingress annotation"
  value       = aws_wafv2_web_acl.observability.arn
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS, or empty when domain_name is unset"
  value       = local.enable_tls ? aws_acm_certificate_validation.observability[0].certificate_arn : ""
}

output "hostname" {
  description = "Public hostname for the stack, or empty when domain_name is unset"
  value       = local.fqdn
}

output "route53_zone_id" {
  description = "Hosted zone the workloads stack creates the ALB alias record in"
  value       = var.route53_zone_id
}
