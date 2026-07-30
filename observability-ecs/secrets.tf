# Bearer token — authenticates OTLP ingest requests on the PUBLIC ALB path
# only (enforced by a WAF rule, see waf.tf). The internal ALB path has no
# token; its security group is the trust boundary.
resource "random_password" "alloy_bearer_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "alloy_bearer_token" {
  name        = "/${var.project_name}/alloy-bearer-token"
  description = "Bearer token for authenticating OTLP ingest on the public ALB"

  # Secrets Manager defaults to a 30-day recovery window, during which the name
  # stays reserved and any re-apply fails with "already scheduled for deletion".
  # This stack is torn down and rebuilt routinely, and the value is a generated
  # token with no recovery value, so delete it immediately instead.
  recovery_window_in_days = 0
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

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = random_password.grafana_admin.result
}
