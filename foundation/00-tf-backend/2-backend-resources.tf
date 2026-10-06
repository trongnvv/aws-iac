# One versioned + encrypted + private bucket per name in var.state_buckets.
resource "aws_s3_bucket" "this" {
  for_each = var.state_buckets
  bucket   = each.value
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Adopt pre-existing buckets from the real AWS resource (by name) into state on apply — no recreate,
# no manual `state mv`. Buckets in state_buckets but not adopt_buckets are just created.
import {
  for_each = var.adopt_buckets
  to       = aws_s3_bucket.this[each.value]
  id       = each.value
}
