# Dead Letter Queue — catches messages that fail after max retries
resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
}

# Main notification queue
resource "aws_sqs_queue" "notifications" {
  name                       = "${var.project_name}-queue"
  visibility_timeout_seconds = var.lambda_timeout * 10
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}
