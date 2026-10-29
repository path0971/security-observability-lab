terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = "security-observability-lab"
      ManagedBy = "Terraform"
      Purpose   = "TerraformState"
    }
  }
}

# Terraform 상태 파일 저장용 버킷
resource "aws_s3_bucket" "tfstate" {
  bucket        = "security-lab-tfstate-${var.aws_account_id}-ap-northeast-2"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# 이전 상태 파일을 복구할 수 있도록 버전 관리 활성화
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 관리형 키를 이용한 저장 시 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 접근 차단
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 암호화되지 않은 HTTP 연결 거부
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
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

output "state_bucket_name" {
  description = "Terraform 상태 파일을 저장할 S3 버킷 이름"
  value       = aws_s3_bucket.tfstate.id
}