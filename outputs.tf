output "sqs_queue_url" {
  description = "URL of the main SQS notification queue"
  value       = aws_sqs_queue.notifications.url
}

output "sqs_dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.notifications_dlq.url
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.notification_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.notification_processor.arn
}

output "sender_email" {
  description = "Verified sender email for SES"
  value       = var.sender_email
}
