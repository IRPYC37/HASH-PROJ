check "ssh_ouvert_au_monde_en_aws" {
  assert {
    condition     = !local.use_managed_services || var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = <<-EOT
      SSH (port 22) est ouvert à 0.0.0.0/0 en mode aws. Restreindre
      allowed_ssh_cidr à l'IP publique de l'opérateur (ex: "203.0.113.10/32")
      via terraform.tfvars ou -var avant un déploiement réel.
    EOT
  }
}

check "environnement_correspond_au_workspace" {
  assert {
    condition     = terraform.workspace == "default" || terraform.workspace == var.environnement
    error_message = <<-EOT
      Le workspace Terraform sélectionné ("${terraform.workspace}") ne
      correspond pas à var.environnement ("${var.environnement}"). Aligner les
      deux avant un apply réel : `terraform workspace select ${var.environnement}`
      ou `-var environnement=${terraform.workspace}` — voir "Mise en place .md" §6.
    EOT
  }
}
