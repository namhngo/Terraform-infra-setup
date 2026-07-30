# IRSA (IAM Roles for Service Accounts) — grants pod-level AWS permissions
# scoped to specific Kubernetes ServiceAccounts, no shared node-level
# credentials. Requires the EKS OIDC provider created in eks.tf.

locals {
  oidc_provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  # One entry per pod-scoped IRSA role. Each maps a ServiceAccount (the map key,
  # in var.k8s_namespace) to the single inline policy it needs. The EBS CSI and
  # LB controller roles are kept separate below — they live in kube-system and
  # use AWS-managed policies rather than this inline shape.
  irsa_roles = {
    loki = {
      policy_suffix = "s3"
      actions       = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      resources     = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]
    }
    tempo = {
      policy_suffix = "s3"
      actions       = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      resources     = [aws_s3_bucket.tempo.arn, "${aws_s3_bucket.tempo.arn}/*"]
    }
    alloy = {
      policy_suffix = "secrets"
      actions       = ["secretsmanager:GetSecretValue"]
      resources     = [aws_secretsmanager_secret.alloy_bearer_token.arn]
    }
    grafana = {
      policy_suffix = "secrets"
      actions       = ["secretsmanager:GetSecretValue"]
      resources     = [aws_secretsmanager_secret.grafana_admin_password.arn]
    }
  }
}

# Trust policy — identical shape for every role, differing only in the
# ServiceAccount named in the `sub` condition (the map key).
data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = local.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${each.key}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name               = "${var.project_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json
}

resource "aws_iam_policy" "irsa" {
  for_each = local.irsa_roles

  name = "${var.project_name}-${each.key}-${each.value.policy_suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = each.value.actions
      Resource = each.value.resources
    }]
  })
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.irsa_roles

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.irsa[each.key].arn
}

# --- EBS CSI Driver: needed for dynamic PVC provisioning (Prometheus storage) ---
# EKS does not bundle this addon by default — it must be installed + granted
# IAM permissions to create/attach/delete EBS volumes on behalf of PVCs.

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# --- AWS Load Balancer Controller ---
# The Helm release and ServiceAccount live in the workloads stack; only the IAM
# role belongs here. Uses the community submodule because the AWS-published
# policy has ~20 statements and changes with new ALB features, unlike the simple
# hand-written roles above.

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-lb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
