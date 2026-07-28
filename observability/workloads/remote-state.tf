# Reads the platform stack's outputs. Everything AWS-side — bucket names, IRSA
# role ARNs, the WAF ACL, the certificate — is owned there and consumed here, so
# neither stack duplicates the other's resources.
#
# Both stacks keep state locally, so this reads the sibling state file directly.
# It does mean `platform` has to be applied first, which the Makefile enforces.

data "terraform_remote_state" "platform" {
  backend = "local"

  config = {
    path = "${path.module}/../platform/terraform.tfstate"
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs

  namespace  = local.platform.k8s_namespace
  role_arns  = local.platform.iam_role_arns
  enable_tls = local.platform.acm_certificate_arn != ""
}

# Secret values are read here rather than passed through platform outputs, which
# would copy them into a second state file.
data "aws_secretsmanager_secret_version" "alloy_bearer_token" {
  secret_id = local.platform.alloy_bearer_token_secret_arn
}

data "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id = local.platform.grafana_admin_password_secret_arn
}
