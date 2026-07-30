output "endpoint" {
  description = "Base URL for Grafana and the OTLP ingest paths"

  # Without a domain the only address is the ALB's generated hostname, which the
  # controller writes back into the Ingress status once provisioning finishes —
  # so it reads as pending on the apply that creates it.
  value = local.enable_tls ? "https://${local.platform.hostname}" : (
    "http://${try(kubernetes_ingress_v1.grafana.status[0].load_balancer[0].ingress[0].hostname, "<pending, re-run terraform output>")}"
  )
}

output "grafana_admin_password_command" {
  description = "Retrieves the Grafana admin password without printing it to a terminal history"
  value       = "aws secretsmanager get-secret-value --secret-id ${local.platform.grafana_admin_password_secret_arn} --query SecretString --output text"
}

output "alloy_bearer_token_command" {
  description = "Retrieves the bearer token required on OTLP ingest requests"
  value       = "aws secretsmanager get-secret-value --secret-id ${local.platform.alloy_bearer_token_secret_arn} --query SecretString --output text"
}

output "kubeconfig_command" {
  description = "Points kubectl at the cluster"
  value       = "aws eks update-kubeconfig --name ${data.aws_eks_cluster.this.name} --region ${var.aws_region}"
}
