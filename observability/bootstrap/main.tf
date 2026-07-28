# Creates the S3 bucket that holds remote state for every other stack in this
# repo. This stack is the one exception that keeps its state local: it cannot
# store state in a bucket it is responsible for creating. It is applied once and
# then left alone, so a local state file is not a practical problem — and if it
# is ever lost, the bucket can simply be re-imported.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are globally unique, so the account ID keeps this from
  # colliding with anyone else's. The Makefile derives the same name at init
  # time, which is why it is not hardcoded in any backend block.
  bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # No force_destroy: losing state is unrecoverable, so deleting this bucket
  # should require emptying it deliberately first.
  tags = {
    Project = var.project_name
    Purpose = "terraform-state"
  }
}

# State files contain generated passwords and tokens in plaintext, so previous
# versions have to be retained and encrypted.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Reject any plaintext request, since state travels over this path on every plan.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# Old state versions are useful for recovery but not forever.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_version_retention_days
    }
  }
}
