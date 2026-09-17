locals {
  use_managed_services = var.deployment_mode == "aws"

  environment_settings = {
    dev = {
      instance_type        = "t3.micro"
      instance_count       = 1
      asg_min_size         = 1
      asg_desired_capacity = 1
      asg_max_size         = 2
      rds_instance_class   = "db.t3.micro"
      backup_retention     = 1
    }
    staging = {
      instance_type        = "t3.small"
      instance_count       = 2
      asg_min_size         = 1
      asg_desired_capacity = 2
      asg_max_size         = 3
      rds_instance_class   = "db.t3.micro"
      backup_retention     = 3
    }
    prod = {
      instance_type        = "t3.medium"
      instance_count       = 2
      asg_min_size         = 2
      asg_desired_capacity = 2
      asg_max_size         = 4
      rds_instance_class   = "db.t3.small"
      backup_retention     = 7
    }
  }

  current_environment = local.environment_settings[var.environnement]
}