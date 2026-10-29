resource "aws_iam_user_policy" "wazuh_eks_logs" {
  name = "read-eks-control-plane-logs"
  user = aws_iam_user.wazuh_reader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeEksLogStreams"
        Effect   = "Allow"
        Action   = "logs:DescribeLogStreams"
        Resource = "arn:aws:logs:ap-northeast-2:${var.aws_account_id}:log-group:/aws/eks/security-lab-eks/cluster:*"
      },
      {
        Sid      = "ReadEksLogEvents"
        Effect   = "Allow"
        Action   = "logs:GetLogEvents"
        Resource = "arn:aws:logs:ap-northeast-2:${var.aws_account_id}:log-group:/aws/eks/security-lab-eks/cluster:log-stream:*"
      }
    ]
  })
}