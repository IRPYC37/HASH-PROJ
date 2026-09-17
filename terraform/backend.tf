terraform {
  backend "s3" {
    bucket                      = "taylor-shift-terraform-state"
    key                         = "terraform.tfstate"
    workspace_key_prefix        = "taylor-shift"
    region                      = "us-east-1"
    use_lockfile                = true
    endpoints                   = { s3 = "http://localhost.floci.io:4566" }
    use_path_style              = true
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
