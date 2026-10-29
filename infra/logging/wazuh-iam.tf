resource "aws_iam_user" "wazuh_reader" {
  name = "security-lab-wazuh-reader"
}

resource "aws_iam_user_policy" "wazuh_reader" {
  name = "read-cloudtrail-logs"
  user = aws_iam_user.wazuh_reader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListLogBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Sid      = "ReadCloudTrailLogs"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.logs.arn}/AWSLogs/${local.account_id}/CloudTrail/*"
      }
    ]
  })
}

output "wazuh_reader_name" {
  value = aws_iam_user.wazuh_reader.name
}