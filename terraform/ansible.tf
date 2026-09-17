resource "ansible_host" "web" {
  for_each = aws_instance.web

  name   = each.key
  groups = ["webservers"]

  variables = {
    floci_instance               = each.value.id
    terraform_instance_id        = each.value.id
    ansible_host                 = local.use_managed_services ? each.value.public_ip : "127.0.0.1"
    ansible_user                 = local.use_managed_services ? "ubuntu" : "root"
    application_db_host          = local.use_managed_services ? aws_db_instance.main[0].address : "db"
    application_db_name          = var.db_name
    application_db_user          = var.db_username
    application_db_password      = coalesce(var.db_password, random_password.db.result)
    application_db_secret_arn    = aws_secretsmanager_secret.database.arn
  }
}

resource "ansible_group" "webservers" {
  name = "webservers"

  variables = {
    application_environnement = var.environnement
    application_titre         = "Taylor Shift's Ticket Shop"
    application_port          = 80
    backup_bucket             = module.backup_bucket.id
    application_use_local_database = !local.use_managed_services
  }
}
