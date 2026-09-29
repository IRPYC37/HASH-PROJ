variable "project" {
  description = "Nom du projet, utilisé comme préfixe des ressources."
  type        = string
  default     = "taylor-shift"
}

variable "environnement" {
  description = "Environnement : dev, staging ou prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environnement)
    error_message = "environnement doit être dev, staging ou prod."
  }
}

variable "region" {
  description = "Région AWS."
  type        = string
  default     = "us-east-1"
}

variable "floci_endpoint" {
  description = "Adresse de l'API Floci."
  type        = string
  default     = "http://localhost.floci.io:4566"
}

variable "deployment_mode" {
  description = "Mode de déploiement : floci ou aws."
  type        = string
  default     = "floci"

  validation {
    condition     = contains(["floci", "aws"], var.deployment_mode)
    error_message = "deployment_mode doit être floci ou aws."
  }
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Plages d'adresses des subnets publics."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Plages d'adresses des subnets privés, utilisés par RDS."
  type        = list(string)
  default     = ["10.42.11.0/24", "10.42.12.0/24"]
}

variable "ssh_public_key_path" {
  description = "Chemin de la clé publique SSH depuis le dossier terraform."
  type        = string
  default     = "../.keys/taylor-shift.pub"
}

variable "ssh_private_key_path" {
  description = "Chemin de la clé privée SSH utilisée par Ansible."
  type        = string
  default     = "../.keys/taylor-shift"
}

variable "db_name" {
  description = "Nom de la base PrestaShop."
  type        = string
  default     = "prestashop"
}

variable "db_username" {
  description = "Utilisateur de la base PrestaShop."
  type        = string
  default     = "prestashop"
}

variable "db_password" {
  description = "Mot de passe RDS, généré automatiquement s'il n'est pas fourni."
  type        = string
  sensitive   = true
  default     = null
}

variable "allowed_ssh_cidr" {
  description = "Plage d'adresses autorisée en SSH sur les EC2."
  type        = string
  default     = "0.0.0.0/0"
}

variable "asg_cpu_target" {
  description = "CPU moyen visé par l'Auto Scaling Group, en pourcentage."
  type        = number
  default     = 60

  validation {
    condition     = var.asg_cpu_target > 10 && var.asg_cpu_target < 95
    error_message = "asg_cpu_target doit être compris entre 10 et 95."
  }
}

variable "floci_http_port_base" {
  description = "Port du site sur le poste en mode floci, pour la première instance."
  type        = number
  default     = 8080

  validation {
    condition     = var.floci_http_port_base >= 1024 && var.floci_http_port_base <= 65000
    error_message = "floci_http_port_base doit être compris entre 1024 et 65000."
  }
}
