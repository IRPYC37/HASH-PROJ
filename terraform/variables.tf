variable "project" {
  description = "Nom court du projet utilisé dans les noms AWS."
  type        = string
  default     = "taylor-shift"
}

variable "environnement" {
  description = "Environnement isolé par le state Terraform."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environnement)
    error_message = "environnement doit être dev, staging ou prod."
  }
}

variable "region" {
  description = "Région AWS du déploiement."
  type        = string
  default     = "us-east-1"
}

variable "floci_endpoint" {
  description = "Endpoint Floci utilisé par les labs locaux."
  type        = string
  default     = "http://localhost.floci.io:4566"
}

variable "deployment_mode" {
  description = "Cible du déploiement : floci pour les labs locaux, aws pour l'architecture managée complète."
  type        = string
  default     = "floci"

  validation {
    condition     = contains(["floci", "aws"], var.deployment_mode)
    error_message = "deployment_mode doit être floci ou aws."
  }
}

variable "vpc_cidr" {
  description = "Plage privée du VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Plages des subnets publics de l'ALB et des EC2."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Plages des subnets privés de RDS."
  type        = list(string)
  default     = ["10.42.11.0/24", "10.42.12.0/24"]
}

variable "instance_type" {
  description = "Type EC2 des serveurs applicatifs."
  type        = string
  default     = "t3.micro"
}

variable "nombre_instances" {
  description = "Nombre d'EC2 configurées par Ansible."
  type        = number
  default     = 1

  validation {
    condition     = var.nombre_instances >= 1 && var.nombre_instances <= 4
    error_message = "nombre_instances doit être compris entre 1 et 4."
  }
}

variable "ssh_public_key_path" {
  description = "Chemin de la clé publique SSH, relatif à terraform/."
  type        = string
  default     = "../.keys/taylor-shift.pub"
}

variable "ssh_private_key_path" {
  description = "Chemin de la clé privée SSH transmis à Ansible sans son contenu."
  type        = string
  default     = "../.keys/taylor-shift"
}

variable "db_name" {
  description = "Nom de la base PrestaShop."
  type        = string
  default     = "prestashop"
}

variable "db_username" {
  description = "Utilisateur administrateur de la base PrestaShop."
  type        = string
  default     = "prestashop"
}

variable "db_password" {
  description = "Mot de passe RDS fourni par variable d'environnement ou fichier tfvars ignoré."
  type        = string
  sensitive   = true
  default     = null
}

variable "application_public_port" {
  description = <<-EOT
    Port local utilisé pour joindre l'application en mode "floci" (via le
    tunnel SSH de scripts/floci-tunnel.sh, Floci ne publiant que le port SSH
    vers l'hôte). Par défaut 8080 ; à changer si ce port est déjà utilisé par
    un autre service sur la machine de développement.
  EOT
  type        = number
  default     = 8080
}

variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR autorisé à joindre le port SSH des EC2 (security group "web").
    Par défaut 0.0.0.0/0 : acceptable en mode "floci" (bac à sable local,
    aucune exposition réelle sur Internet), mais À RESTREINDRE
    IMPÉRATIVEMENT en mode "aws" à l'IP publique de l'opérateur, par
    exemple "203.0.113.10/32" — via terraform.tfvars ou
    -var='allowed_ssh_cidr=...'. Un `terraform plan`/`apply` en mode "aws"
    avec la valeur par défaut affiche un avertissement (voir checks.tf).
  EOT
  type        = string
  default     = "0.0.0.0/0"
}
