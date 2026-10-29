terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "ingress/terraform.tfstate"
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

data "aws_eks_cluster" "lab" {
  name = "security-lab-eks"
}

locals {
  oidc_issuer = data.aws_eks_cluster.lab.identity[0].oidc[0].issuer
  oidc_host   = trimprefix(local.oidc_issuer, "https://")
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = local.oidc_issuer

  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "security-lab-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.controller_trust.json
}

resource "aws_iam_policy" "controller" {
  name   = "security-lab-aws-load-balancer-controller"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}

output "controller_role_arn" {
  value = aws_iam_role.controller.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "vpc_id" {
  value = data.aws_eks_cluster.lab.vpc_config[0].vpc_id
}