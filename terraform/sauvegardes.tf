moved {
  from = aws_s3_bucket_versioning.backup
  to   = module.backup_bucket.aws_s3_bucket_versioning.this
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.backup
  to   = module.backup_bucket.aws_s3_bucket_server_side_encryption_configuration.this
}

moved {
  from = aws_s3_bucket_public_access_block.backup
  to   = module.backup_bucket.aws_s3_bucket_public_access_block.this
}
