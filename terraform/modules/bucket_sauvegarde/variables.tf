variable "bucket_name" {
  description = "Nom globalement unique du bucket de sauvegarde."
  type        = string
}

variable "noncurrent_retention_days" {
  description = "Durée de conservation d'une ancienne version d'objet, en jours."
  type        = number
  default     = 30
}
