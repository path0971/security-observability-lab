resource "aws_s3_bucket" "security_findings" {
  bucket        = "security-lab-findings-${var.aws_account_id}-ap-northeast-2"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "security_findings" {
  bucket = aws_s3_bucket.security_findings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "security_findings" {
  bucket = aws_s3_bucket.security_findings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "security_findings" {
  bucket = aws_s3_bucket.security_findings.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.security_findings.arn,
        "${aws_s3_bucket.security_findings.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "security_findings" {
  bucket = aws_s3_bucket.security_findings.id

  rule {
    id     = "expire-findings-after-30-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_sqs_queue" "security_findings" {
  name                       = "security-lab-findings"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue_policy" "security_findings" {
  queue_url = aws_sqs_queue.security_findings.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFindingsBucketNotifications"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.security_findings.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.security_findings.arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.security_findings.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "security_findings" {
  bucket = aws_s3_bucket.security_findings.id

  queue {
    id            = "notify-wazuh"
    queue_arn     = aws_sqs_queue.security_findings.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "findings/"
  }

  depends_on = [aws_sqs_queue_policy.security_findings]
}

resource "aws_iam_user_policy" "wazuh_security_findings" {
  name = "read-security-hub-findings"
  user = "security-lab-wazuh-reader"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadFindings"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.security_findings.arn}/findings/*"
      },
      {
        Sid      = "GetBucketLocation"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = aws_s3_bucket.security_findings.arn
      },
      {
        Sid    = "ConsumeBucketNotifications"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.security_findings.arn
      }
    ]
  })
}