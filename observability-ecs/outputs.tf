# Outputs are added incrementally as each resource type is implemented.

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALBs)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Fargate tasks)"
  value       = module.vpc.private_subnets
}

output "loki_bucket" {
  description = "S3 bucket for Loki chunks"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket" {
  description = "S3 bucket for Tempo blocks"
  value       = aws_s3_bucket.tempo.id
}
