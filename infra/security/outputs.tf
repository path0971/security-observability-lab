output "guardduty_detector_id" {
  value = aws_guardduty_detector.lab.id
}

output "guardduty_enabled" {
  value = aws_guardduty_detector.lab.enable
}

output "securityhub_arn" {
  value = aws_securityhub_account.lab.arn
}

output "findings_bucket_name" {
  value = aws_s3_bucket.security_findings.id
}

output "findings_queue_name" {
  value = aws_sqs_queue.security_findings.name
}

output "findings_delivery_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.security_findings.name
}