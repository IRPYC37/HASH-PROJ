check "environnement_correspond_au_workspace" {
  assert {
    condition     = terraform.workspace == "default" || terraform.workspace == var.environnement
    error_message = "Le workspace ${terraform.workspace} ne correspond pas à var.environnement (${var.environnement})."
  }
}
