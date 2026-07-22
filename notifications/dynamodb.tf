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
