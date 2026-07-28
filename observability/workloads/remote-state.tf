# Reads the platform stack's outputs. Everything AWS-side — bucket names, IRSA
# role ARNs, the WAF ACL, the certificate — is owned there and consumed here, so
# neither stack duplicates the other's resources.

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    # Same derivation as bootstrap/main.tf and the Makefile.
    bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
    key    = "observability/platform.tfstate"
    region = var.aws_region
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
