resource "aws_db_subnet_group" "main" {
  count      = local.use_managed_services ? 1 : 0
  name       = "${local.prefixe}-db"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags       = { Name = "${local.prefixe}-db" }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "main" {
  count                   = local.use_managed_services ? 1 : 0
  identifier              = "${local.prefixe}-mariadb"
  engine                  = "mariadb"
  engine_version          = "10.11"
  instance_class          = local.current_environment.rds_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 50
  db_name                 = var.db_name
  username                = var.db_username
  password                = coalesce(var.db_password, random_password.db.result)
  db_subnet_group_name    = aws_db_subnet_group.main[0].name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = local.current_environment.backup_retention
  storage_encrypted       = true
}

resource "aws_secretsmanager_secret" "database" {
  name                    = "${local.prefixe}/database"
  recovery_window_in_days = 0
  tags                    = { Name = "${local.prefixe}-database" }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    host     = local.use_managed_services ? aws_db_instance.main[0].address : "127.0.0.1"
    port     = local.use_managed_services ? aws_db_instance.main[0].port : 3306
    database = var.db_name
    username = var.db_username
    password = coalesce(var.db_password, random_password.db.result)
  })
}