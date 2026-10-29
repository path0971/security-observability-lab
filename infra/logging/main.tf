terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "logging/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "security-observability-lab"
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  account_id = var.aws_account_id
  trail_name = "security-lab-management"
  trail_arn  = "arn:aws:cloudtrail:ap-northeast-2:${var.aws_account_id}:trail/security-lab-management"
}

# CloudTrail 로그 전용 버킷
resource "aws_s3_bucket" "logs" {
  bucket        = "security-lab-cloudtrail-${var.aws_account_id}-ap-northeast-2"
  force_destroy = false
}

# S3 관리형 키를 사용하는 저장 시 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 접근 차단
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 실습 로그는 생성 후 30일이 지나면 삭제 대상
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs-after-30-days"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    expiration {
      days = 30
    }
  }
}

# 해당 CloudTrail만 지정 경로에 로그를 기록하도록 허용
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid    = "CloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "management" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.logs.id

  enable_logging                = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_s3_bucket_public_access_block.logs,
    aws_s3_bucket_server_side_encryption_configuration.logs,
    aws_s3_bucket_lifecycle_configuration.logs
  ]
}

output "cloudtrail_name" {
  value = aws_cloudtrail.management.name
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.management.arn
}

output "log_bucket_name" {
  value = aws_s3_bucket.logs.id
}