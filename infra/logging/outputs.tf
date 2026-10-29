output "app_log_group_name" {
  value = aws_cloudwatch_log_group.app_logs.name
}

output "app_log_collector_role_arn" {
  value = aws_iam_role.app_log_collector.arn
}