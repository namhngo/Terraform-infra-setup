# ECS task IAM: one shared execution role (lets ECS pull images from ECR and
# write to CloudWatch Logs — used by the ECS agent, not the app container),
# plus a per-service task role for the app containers that actually need AWS
# permissions (S3, Secrets Manager). Simpler than IRSA in observability-eks:
# ECS task roles all share the same trust policy (any ECS task in this
# account can assume them), no OIDC provider or per-ServiceAccount trust
# condition needed — the isolation instead comes from each service only ever
# being assigned its own role in ecs.tf.

locals {
  # One entry per service that needs AWS permissions. Prometheus isn't here —
  # it has no task role at all, since it needs no AWS API access.
  task_roles = {
    alloy = {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.alloy_bearer_token.arn]
    }
    loki = {
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      resources = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]
    }
    tempo = {
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      resources = [aws_s3_bucket.tempo.arn, "${aws_s3_bucket.tempo.arn}/*"]
    }
    grafana = {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.grafana_admin_password.arn]
    }
  }
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- Shared execution role (ECS agent: ECR pull, CloudWatch Logs write) ---

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Per-service task roles (app-level AWS permissions) ---

resource "aws_iam_role" "task" {
  for_each = local.task_roles

  name               = "${var.project_name}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_policy" "task" {
  for_each = local.task_roles

  name = "${var.project_name}-${each.key}-task"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = each.value.actions
      Resource = each.value.resources
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = local.task_roles

  role       = aws_iam_role.task[each.key].name
  policy_arn = aws_iam_policy.task[each.key].arn
}
