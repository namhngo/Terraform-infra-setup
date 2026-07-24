# Bearer token — authenticates OTLP ingest requests at the ALB/nginx layer
# (Alloy itself doesn't validate tokens; enforcement happens upstream).
resource "random_password" "alloy_bearer_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "alloy_bearer_token" {
  name        = "/${var.project_name}/alloy-bearer-token"
  description = "Bearer token for authenticating OTLP ingest to Alloy"
}

resource "aws_secretsmanager_secret_version" "alloy_bearer_token" {
  secret_id     = aws_secretsmanager_secret.alloy_bearer_token.id
  secret_string = random_password.alloy_bearer_token.result
}

# Grafana admin password
resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name        = "/${var.project_name}/grafana-admin-password"
  description = "Grafana admin login password"
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = random_password.grafana_admin.result
}
