output "db_identifier" {
  value = aws_db_instance.lab.identifier
}

output "db_address" {
  value = aws_db_instance.lab.address
}

output "db_port" {
  value = aws_db_instance.lab.port
}

output "db_name" {
  value = aws_db_instance.lab.db_name
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "master_secret_arn" {
  value = aws_db_instance.lab.master_user_secret[0].secret_arn
}