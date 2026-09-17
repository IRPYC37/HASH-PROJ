resource "aws_iam_role" "web" {
  count = local.use_managed_services ? 1 : 0
  name  = "${local.prefixe}-web"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  count = local.use_managed_services ? 1 : 0
  name  = "${local.prefixe}-web"
  role  = aws_iam_role.web[0].name
}

resource "aws_iam_role_policy" "web_backup" {
  count = local.use_managed_services ? 1 : 0
  name  = "${local.prefixe}-backup"
  role  = aws_iam_role.web[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
      Resource = "${module.backup_bucket.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "web_database_secret" {
  count = local.use_managed_services ? 1 : 0
  name  = "${local.prefixe}-database-secret"
  role  = aws_iam_role.web[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.database.arn
    }]
  })
}

module "backup_bucket" {
  source      = "./modules/bucket_sauvegarde"
  bucket_name = "${local.prefixe}-backup-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}
