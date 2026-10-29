variable "aws_profile" {
  description = "Terraform이 사용할 AWS CLI 프로필 이름"
  type        = string
}

variable "aws_account_id" {
  description = "배포 대상 AWS 계정 ID (12자리)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id는 12자리 숫자여야 합니다."
  }
}

variable "vpc_id" {
  description = "network 스택이 만든 VPC ID"
  type        = string
}

variable "eks_security_group_id" {
  description = "MySQL 접근을 허용할 EKS 클러스터 보안 그룹 ID"
  type        = string
}

variable "db_subnet_ids" {
  description = "DB 서브넷 ID 목록 (db_a, db_c)"
  type        = list(string)
}
