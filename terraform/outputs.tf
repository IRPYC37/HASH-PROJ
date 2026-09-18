output "alb_endpoint" {
  description = "Endpoint HTTP public de l'application. En mode floci, Floci ne publie pas ce port automatiquement : lancer scripts/floci-tunnel.sh avant d'y accéder (voir README)."
  value       = local.use_managed_services ? "http://${aws_lb.application[0].dns_name}" : "http://localhost:${var.application_public_port}"
}

output "alb_dns_name" {
  description = "Nom DNS de l'ALB."
  value       = local.use_managed_services ? aws_lb.application[0].dns_name : null
}

output "rds_endpoint" {
  description = "Endpoint RDS sans le mot de passe."
  value       = local.use_managed_services ? aws_db_instance.main[0].address : null
}

output "web_instances" {
  description = "Adresses publiques des EC2 gérées par Ansible."
  value       = { for name, instance in aws_instance.web : name => instance.public_ip }
}

output "database_secret_arn" {
  description = "ARN du secret RDS, jamais sa valeur."
  value       = aws_secretsmanager_secret.database.arn
}

output "backup_bucket" {
  description = "Bucket S3 chiffré et versionné des sauvegardes."
  value       = module.backup_bucket.id
}
