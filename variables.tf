variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "sio-notifications"
}

variable "sender_email" {
  description = "Email address to send notifications FROM (must be verified in SES)"
  type        = string
}

variable "test_recipient_email" {
  description = "Email address to send test notifications TO (must be verified in SES sandbox)"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "sqs_max_receive_count" {
  description = "Number of times SQS retries before sending to DLQ"
  type        = number
  default     = 3
}
