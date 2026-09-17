resource "aws_ssm_parameter" "environment" {
  name  = "/${var.project}/${var.environnement}/environment"
  type  = "String"
  value = var.environnement
  tags  = { Name = "${local.prefixe}-environment" }
}
