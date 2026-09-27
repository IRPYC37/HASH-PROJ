output "alb_endpoint" {
  description = "URL de l'application en mode aws."
  value       = local.use_managed_services ? "http://${aws_lb.application[0].dns_name}" : null
}

output "floci_urls" {
  description = "URL de l'application par instance en mode floci (relais local créé par Ansible)."
  value       = local.use_managed_services ? null : { for name, port in local.floci_http_ports : name => "http://localhost:${port}" }
}

output "rds_endpoint" {
  description = "Endpoint RDS sans le mot de passe."
  value       = local.use_managed_services ? aws_db_instance.main[0].address : null
}

output "web_instances" {
  description = "Identifiant et adresse privée des EC2 configurées par Ansible."
  value       = { for name, instance in aws_instance.web : name => { id = instance.id, private_ip = instance.private_ip } }
}

output "database_secret_arn" {
  description = "ARN du secret RDS (mode aws), jamais sa valeur."
  value       = local.use_managed_services ? aws_secretsmanager_secret.database[0].arn : null
}

output "backup_bucket" {
  description = "Bucket S3 chiffré et versionné des sauvegardes."
  value       = module.backup_bucket.id
}
