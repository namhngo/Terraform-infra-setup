# =============================================================
# DynamoDB Table — idempotency tracking
# Prevents duplicate sends if SQS redelivers a message
# (SQS is at-least-once delivery, so this can happen).
# =============================================================

resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.project_name}-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

# =============================================================
# DynamoDB Table — delivery tracking
# One row per delivery attempt, so you can answer
# "was this notification sent? on which channel? did it fail?"
# =============================================================

resource "aws_dynamodb_table" "notification_log" {
  name         = "${var.project_name}-notification-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "log_id"

  attribute {
    name = "log_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

# =============================================================
# DynamoDB Table — batch buffer
# Incoming events land here first instead of being sent right away.
# A scheduled Lambda run (see cloudwatch.tf) flushes this table every
# few minutes, grouping by recipient into a single digest email.
# =============================================================

resource "aws_dynamodb_table" "batch_buffer" {
  name         = "${var.project_name}-batch-buffer"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "buffer_id"

  attribute {
    name = "buffer_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
