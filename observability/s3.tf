# S3 buckets for Loki (log chunks) and Tempo (trace blocks).
# Access is granted exclusively via IRSA (see iam.tf) — no bucket policies
# or public access of any kind.
#
# force_destroy lets Terraform empty the buckets during a destroy. Without it
# the destroy fails with BucketNotEmpty as soon as any telemetry has landed.
# Acceptable here because the buckets only ever hold reproducible observability
# data with a retention window measured in days.

resource "aws_s3_bucket" "loki" {
  bucket        = "${var.project_name}-loki"
  force_destroy = true
}

resource "aws_s3_bucket" "tempo" {
  bucket        = "${var.project_name}-tempo"
  force_destroy = true
}

# --- Block all public access ---

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Lifecycle rules (cost control — matches retention configured in
#     Loki/Tempo themselves, see configs/loki/loki.yml and configs/tempo/tempo.yml) ---

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-after-90d"
    status = "Enabled"

    filter {}

    expiration {
      days = var.loki_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    id     = "expire-after-30d"
    status = "Enabled"

    filter {}

    expiration {
      days = var.tempo_retention_days
    }
  }
}

# --- Default encryption (SSE-S3) ---

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
