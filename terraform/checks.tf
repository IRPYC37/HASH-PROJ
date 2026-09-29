check "ssh_ouvert_au_monde_en_aws" {
  assert {
    condition     = !local.use_managed_services || var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "SSH ouvert à 0.0.0.0/0 en mode aws : restreindre allowed_ssh_cidr."
  }
}

check "environnement_correspond_au_workspace" {
  assert {
    condition     = terraform.workspace == "default" || terraform.workspace == var.environnement
    error_message = "Le workspace ${terraform.workspace} ne correspond pas à var.environnement (${var.environnement})."
  }
}
