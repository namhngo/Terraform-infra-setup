# =============================================================
# SNS Topic — where alarm notifications get sent
# =============================================================

resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# =============================================================
# Alarm — DLQ depth
# Fires when any message lands in the Dead Letter Queue,
# meaning a notification failed all its retries.
# =============================================================

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name        = "${var.project_name}-dlq-depth"
  alarm_description = "Messages are landing in the Dead Letter Queue — notifications failed all retries"
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = aws_sqs_queue.notifications_dlq.name
  }
  statistic           = "Maximum"
  period              = 300 # 5 minutes
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# =============================================================
# Alarm — Lambda error rate
# Fires when the notification processor throws errors,
# meaning events are not being handled correctly.
# =============================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "${var.project_name}-lambda-errors"
  alarm_description = "Lambda function is throwing errors while processing notifications"
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.notification_processor.function_name
  }
  statistic           = "Sum"
  period              = 300 # 5 minutes
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
