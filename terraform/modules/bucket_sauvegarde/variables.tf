variable "bucket_name" {
  description = "Nom du bucket de sauvegarde."
  type        = string
}

variable "noncurrent_retention_days" {
  description = "Nombre de jours de conservation des anciennes versions."
  type        = number
  default     = 30
}
