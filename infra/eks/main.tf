terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "eks/terraform.tfstate"
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
      Component   = "eks"
    }
  }
}

locals {
  cluster_name = "security-lab-eks"
  version      = "1.35"
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

# 이미 생성한 관리 EC2의 역할과 보안 그룹 조회
data "aws_iam_role" "management" {
  name = "security-lab-management-ssm"
}

data "aws_security_group" "management" {
  filter {
    name   = "group-name"
    values = ["security-lab-management"]
  }

  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.network.outputs.vpc_id]
  }
}

# EKS 제어 영역 역할
resource "aws_iam_role" "cluster" {
  name = "security-lab-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 로그 저장 기간 제한
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "lab" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = local.version

  # 기본 CNI, CoreDNS, kube-proxy 설치
  bootstrap_self_managed_addons = true

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids = [
      data.terraform_remote_state.network.outputs.subnet_ids["app_a"],
      data.terraform_remote_state.network.outputs.subnet_ids["app_c"]
    ]

    endpoint_private_access = true
    endpoint_public_access  = false
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.eks
  ]
}

# 관리 EC2에서 EKS API로 HTTPS 접속 허용
resource "aws_vpc_security_group_ingress_rule" "management_api" {
  security_group_id = aws_eks_cluster.lab.vpc_config[0].cluster_security_group_id

  referenced_security_group_id = data.aws_security_group.management.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Management EC2 to private Kubernetes API"
}

# 관리 EC2에서 kubeconfig를 생성할 때 필요한 AWS API 권한
resource "aws_iam_role_policy" "management_describe" {
  name = "describe-security-lab-eks"
  role = data.aws_iam_role.management.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.lab.arn
    }]
  })
}

# 관리 EC2 역할에 Kubernetes 접근 권한 부여
resource "aws_eks_access_entry" "management" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = data.aws_iam_role.management.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "management" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = aws_eks_access_entry.management.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# 워커 노드 역할
resource "aws_iam_role" "node" {
  name = "security-lab-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
    "AmazonEKS_CNI_Policy"
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# 노드 디스크 암호화와 CPU 크레딧 설정
resource "aws_launch_template" "node" {
  name_prefix = "security-lab-eks-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  credit_specification {
    cpu_credits = "standard"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name      = "security-lab-eks-node"
      Project   = "security-observability-lab"
      ManagedBy = "Terraform"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Project   = "security-observability-lab"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_eks_node_group" "lab" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "lab-workers"
  node_role_arn   = aws_iam_role.node.arn

  subnet_ids = [
    data.terraform_remote_state.network.outputs.subnet_ids["app_a"]
  ]

  version        = local.version
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = tostring(aws_launch_template.node.latest_version)
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node
  ]
}

output "cluster_name" {
  value = aws_eks_cluster.lab.name
}

output "cluster_version" {
  value = aws_eks_cluster.lab.version
}

output "cluster_status" {
  value = aws_eks_cluster.lab.status
}

output "node_group_status" {
  value = aws_eks_node_group.lab.status
}