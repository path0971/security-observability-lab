terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "management/terraform.tfstate"
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
      Component   = "management"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "security-lab-tfstate-${var.aws_account_id}-ap-northeast-2"
    key     = "network/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = var.aws_profile
  }
}

# AWS가 제공하는 최신 AL2023 x86_64 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# NAT에 사용할 퍼블릭 IPv4
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "security-lab-nat-eip"
  }
}

resource "aws_nat_gateway" "lab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.terraform_remote_state.network.outputs.subnet_ids["public_a"]

  tags = {
    Name = "security-lab-nat"
  }
}

# 앱 서브넷의 외부 통신 경로
# DB 라우팅 테이블에는 추가하지 않음
resource "aws_route" "app_internet" {
  route_table_id         = data.terraform_remote_state.network.outputs.route_table_ids["app"]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lab.id
}

# EC2가 사용할 SSM 역할
resource "aws_iam_role" "management" {
  name = "security-lab-management-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "management" {
  name = "security-lab-management"
  role = aws_iam_role.management.name
}

# 인바운드 규칙 없음
resource "aws_security_group" "management" {
  name        = "security-lab-management"
  description = "Management EC2: no inbound, HTTPS outbound"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "security-lab-management"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.management.id
  description       = "HTTPS for SSM and downloads"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "management" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type               = "t3.micro"
  subnet_id                   = data.terraform_remote_state.network.outputs.subnet_ids["app_a"]
  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.management.id]
  iam_instance_profile   = aws_iam_instance_profile.management.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eu
    systemctl enable --now amazon-ssm-agent
  EOF

  tags = {
    Name = "security-lab-management"
  }

  depends_on = [
    aws_route.app_internet,
    aws_vpc_security_group_egress_rule.https,
    aws_iam_role_policy_attachment.ssm
  ]
}

output "management_instance_id" {
  value = aws_instance.management.id
}

output "management_private_ip" {
  value = aws_instance.management.private_ip
}

output "nat_gateway_id" {
  value = aws_nat_gateway.lab.id
}