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

variable "allowed_ssh_cidr" {
  description = "CIDR autorisé en SSH sur les EC2. 0.0.0.0/0 n'est accepté qu'en mode floci (bac à sable local)."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && (var.deployment_mode == "floci" || var.allowed_ssh_cidr != "0.0.0.0/0")
    error_message = "allowed_ssh_cidr doit être un CIDR valide, et restreint (ex. 203.0.113.10/32) en mode aws."
  }
}

variable "asg_cpu_target" {
  description = "CPU moyen (%) visé par la politique de suivi de cible de l'ASG (mode aws)."
  type        = number
  default     = 60

  validation {
    condition     = var.asg_cpu_target > 10 && var.asg_cpu_target < 95
    error_message = "asg_cpu_target doit être compris entre 10 et 95."
  }
}

variable "floci_http_port_base" {
  description = "Premier port du poste publiant le site en mode floci (web1 = base, web2 = base + 1, ...)."
  type        = number
  default     = 30080

  validation {
    condition     = var.floci_http_port_base >= 1024 && var.floci_http_port_base <= 65000
    error_message = "floci_http_port_base doit être compris entre 1024 et 65000."
  }
}
