# =============================================================
# Scheduled Trigger — digest flush
# Every `batch_window_minutes`, invoke the same Lambda function
# in "flush" mode: it reads everything in the batch buffer,
# groups by recipient, and sends one digest email per person.
# =============================================================

resource "aws_cloudwatch_event_rule" "digest_schedule" {
  name                = "${var.project_name}-digest-schedule"
  description         = "Triggers the notification Lambda to flush buffered events as digests"
  schedule_expression = "rate(${var.batch_window_minutes} minutes)"
}

resource "aws_cloudwatch_event_target" "digest_schedule_target" {
  rule = aws_cloudwatch_event_rule.digest_schedule.name
  arn  = aws_lambda_function.notification_processor.arn

  # Tells the handler this invocation is a scheduled flush, not an SQS batch
  input = jsonencode({
    source = "digest.schedule"
  })
}

# Allow CloudWatch Events to invoke the Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.digest_schedule.arn
}
