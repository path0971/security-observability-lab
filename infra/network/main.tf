terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "network/terraform.tfstate"
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
  name = "security-lab"

  subnets = {
    public_a = {
      cidr = "10.20.1.0/24"
      az   = "ap-northeast-2a"
      tier = "public"
    }
    public_c = {
      cidr = "10.20.2.0/24"
      az   = "ap-northeast-2c"
      tier = "public"
    }
    app_a = {
      cidr = "10.20.11.0/24"
      az   = "ap-northeast-2a"
      tier = "app"
    }
    app_c = {
      cidr = "10.20.12.0/24"
      az   = "ap-northeast-2c"
      tier = "app"
    }
    db_a = {
      cidr = "10.20.21.0/24"
      az   = "ap-northeast-2a"
      tier = "db"
    }
    db_c = {
      cidr = "10.20.22.0/24"
      az   = "ap-northeast-2c"
      tier = "db"
    }
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "lab" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.lab.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(
    {
      Name = "${local.name}-${replace(each.key, "_", "-")}"
      Tier = each.value.tier
    },
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb" = "1"
    } : {},
    each.value.tier == "app" ? {
      "kubernetes.io/role/internal-elb" = "1"
    } : {}
  )
}

# 용도별 라우팅 테이블: public, app, db
resource "aws_route_table" "lab" {
  for_each = toset(["public", "app", "db"])

  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name}-${each.key}-rt"
  }
}

# 퍼블릭 서브넷에만 인터넷 게이트웨이 경로 추가
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.lab["public"].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

# 각 서브넷을 해당 용도의 라우팅 테이블에 연결
resource "aws_route_table_association" "lab" {
  for_each = local.subnets

  subnet_id      = aws_subnet.lab[each.key].id
  route_table_id = aws_route_table.lab[each.value.tier].id
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "subnet_ids" {
  value = {
    for name, subnet in aws_subnet.lab :
    name => subnet.id
  }
}

output "route_table_ids" {
  value = {
    for tier, route_table in aws_route_table.lab :
    tier => route_table.id
  }
}