provider "aws" {
  region = var.region

  access_key                  = var.use_floci ? "test" : null
  secret_key                  = var.use_floci ? "test" : null
  skip_credentials_validation = var.use_floci
  skip_metadata_api_check     = var.use_floci
  skip_requesting_account_id  = var.use_floci
  s3_use_path_style           = var.use_floci

  dynamic "endpoints" {
    for_each = var.use_floci ? [1] : []
    content {
      ec2      = var.floci_endpoint
      eks      = var.floci_endpoint
      ecr      = var.floci_endpoint
      iam      = var.floci_endpoint
      sts      = var.floci_endpoint
      s3       = var.floci_endpoint
      dynamodb = var.floci_endpoint
      elbv2    = var.floci_endpoint
    }
  }

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
