resource "aws_cloudwatch_log_group" "findings_firehose" {
  name              = "/aws/kinesisfirehose/security-lab-findings"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "findings_firehose" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.findings_firehose.name
}

resource "aws_iam_role" "findings_firehose" {
  name = "security-lab-findings-firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.aws_account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "findings_firehose" {
  name = "deliver-findings-to-s3"
  role = aws_iam_role.findings_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = aws_s3_bucket.security_findings.arn
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.security_findings.arn}/findings/*",
          "${aws_s3_bucket.security_findings.arn}/errors/*"
        ]
      },
      {
        Sid      = "DeliveryErrorLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = aws_cloudwatch_log_stream.findings_firehose.arn
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "security_findings" {
  name        = "security-lab-findings"
  destination = "extended_s3"

  server_side_encryption {
    enabled  = true
    key_type = "AWS_OWNED_CMK"
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.findings_firehose.arn
    bucket_arn = aws_s3_bucket.security_findings.arn

    prefix              = "findings/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = 300
    compression_format = "UNCOMPRESSED"

    processing_configuration {
      enabled = true

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.findings_firehose.name
      log_stream_name = aws_cloudwatch_log_stream.findings_firehose.name
    }
  }

  depends_on = [
    aws_iam_role_policy.findings_firehose,
    aws_s3_bucket_public_access_block.security_findings,
    aws_s3_bucket_server_side_encryption_configuration.security_findings,
    aws_s3_bucket_policy.security_findings,
    aws_s3_bucket_notification.security_findings
  ]
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "security-lab-guardduty-findings"
  description = "Forward GuardDuty findings imported into Security Hub"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    account       = [var.aws_account_id]
    region        = ["ap-northeast-2"]
    detail = {
      findings = {
        ProductArn = [
          "arn:aws:securityhub:ap-northeast-2::product/aws/guardduty"
        ]
      }
    }
  })
}

resource "aws_iam_role" "findings_eventbridge" {
  name = "security-lab-findings-eventbridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
        }
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.guardduty_findings.arn
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "findings_eventbridge" {
  name = "send-findings-to-firehose"
  role = aws_iam_role.findings_eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ]
      Resource = aws_kinesis_firehose_delivery_stream.security_findings.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "findings_firehose" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "FindingsFirehose"
  arn       = aws_kinesis_firehose_delivery_stream.security_findings.arn
  role_arn  = aws_iam_role.findings_eventbridge.arn

  depends_on = [aws_iam_role_policy.findings_eventbridge]
}