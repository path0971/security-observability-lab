terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "rds/terraform.tfstate"
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
  vpc_id                = var.vpc_id
  eks_security_group_id = var.eks_security_group_id

  db_subnet_ids = var.db_subnet_ids
}

resource "aws_db_subnet_group" "lab" {
  name        = "security-lab-db"
  description = "Private DB subnets for security lab"
  subnet_ids  = local.db_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "security-lab-rds"
  description = "MySQL access from the EKS security group"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_eks" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = local.eks_security_group_id

  ip_protocol = "tcp"
  from_port   = 3306
  to_port     = 3306
  description = "MySQL from EKS nodes and their pods"
}

resource "aws_db_parameter_group" "mysql" {
  name        = "security-lab-mysql84"
  family      = "mysql8.4"
  description = "MySQL 8.4 lab parameters"

  parameter {
    name         = "require_secure_transport"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_db_instance" "lab" {
  identifier = "security-lab-mysql"

  engine         = "mysql"
  engine_version = "8.4.11"
  instance_class = "db.t4g.micro"

  db_name  = "securitylab"
  username = "labadmin"
  port     = 3306

  manage_master_user_password = true

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.lab.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  availability_zone   = "ap-northeast-2a"
  multi_az            = false
  publicly_accessible = false

  backup_retention_period = 1
  copy_tags_to_snapshot   = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "security-lab-mysql-final"

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  engine_lifecycle_support    = "open-source-rds-extended-support-disabled"

  monitoring_interval          = 0
  performance_insights_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}