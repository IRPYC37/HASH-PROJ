output "id" {
  description = "Nom du bucket de sauvegarde."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "ARN du bucket de sauvegarde."
  value       = aws_s3_bucket.this.arn
}
