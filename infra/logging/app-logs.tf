data "aws_eks_cluster" "app_logs" {
  name = "security-lab-eks"
}

data "aws_iam_openid_connect_provider" "app_logs" {
  url = data.aws_eks_cluster.app_logs.identity[0].oidc[0].issuer
}

locals {
  app_logs_oidc_issuer = replace(
    data.aws_eks_cluster.app_logs.identity[0].oidc[0].issuer,
    "https://",
    ""
  )
}

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/security-lab/eks/security-lab-api"
  retention_in_days = 7
}

resource "aws_iam_role" "app_log_collector" {
  name = "security-lab-api-log-collector"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.app_logs.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.app_logs_oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.app_logs_oidc_issuer}:sub" = "system:serviceaccount:security-lab:log-collector"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_log_collector" {
  name = "write-security-lab-api-logs"
  role = aws_iam_role.app_log_collector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeAppLogStreams"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.app_logs.arn}:*"
      },
      {
        Sid    = "WriteAppLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.app_logs.arn}:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_user_policy" "wazuh_app_logs" {
  name = "read-security-lab-api-logs"
  user = "security-lab-wazuh-reader"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeAppLogStreams"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.app_logs.arn}:*"
      },
      {
        Sid      = "ReadAppLogEvents"
        Effect   = "Allow"
        Action   = ["logs:GetLogEvents"]
        Resource = "${aws_cloudwatch_log_group.app_logs.arn}:log-stream:*"
      }
    ]
  })
}