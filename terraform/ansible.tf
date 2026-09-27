locals {
  floci_http_ports = { for index, name in sort(keys(aws_instance.web)) : name => var.floci_http_port_base + index }
}

resource "ansible_host" "web" {
  for_each = aws_instance.web

  name   = each.key
  groups = ["webservers"]

  variables = {
    floci_instance               = each.value.id
    ansible_host                 = local.use_managed_services ? each.value.public_ip : "127.0.0.1"
    ansible_user                 = local.use_managed_services ? "ubuntu" : "root"
    ansible_ssh_private_key_file = trimprefix(var.ssh_private_key_path, "../")
    application_db_host          = local.use_managed_services ? aws_db_instance.main[0].address : "db"
    application_db_name          = var.db_name
    application_db_user          = var.db_username
    application_db_secret_arn    = local.use_managed_services ? aws_secretsmanager_secret.database[0].arn : ""
    application_floci_http_port  = local.floci_http_ports[each.key]
  }
}

resource "ansible_group" "webservers" {
  name = "webservers"

  variables = {
    application_aws_region         = var.region
    sauvegarde_bucket              = module.backup_bucket.id
    application_use_local_database = !local.use_managed_services
    application_alb_dns            = local.use_managed_services ? aws_lb.application[0].dns_name : ""
  }
}
