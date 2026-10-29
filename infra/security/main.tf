terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "security/terraform.tfstate"
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

resource "aws_guardduty_detector" "lab" {
  # 기능 설정 확인 후 true로 변경
  enable = true

  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

locals {
  disabled_guardduty_features = toset([
    "S3_DATA_EVENTS",
    "EKS_AUDIT_LOGS",
    "EBS_MALWARE_PROTECTION",
    "RDS_LOGIN_EVENTS",
    "LAMBDA_NETWORK_LOGS",
    "RUNTIME_MONITORING"
  ])
}

resource "aws_guardduty_detector_feature" "optional" {
  for_each = local.disabled_guardduty_features

  detector_id = aws_guardduty_detector.lab.id
  name        = each.value
  status      = "DISABLED"

  dynamic "additional_configuration" {
    for_each = each.value == "RUNTIME_MONITORING" ? [
      "EC2_AGENT_MANAGEMENT",
      "ECS_FARGATE_AGENT_MANAGEMENT",
      "EKS_ADDON_MANAGEMENT",
    ] : []

    content {
      name   = additional_configuration.value
      status = "DISABLED"
    }
  }
}

resource "aws_securityhub_account" "lab" {
  enable_default_standards = false
}