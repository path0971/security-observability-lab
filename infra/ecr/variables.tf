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
