bucket                      = "ivolve-tfstate"
key                         = "cloud-devops/terraform.tfstate"
region                      = "us-east-1"
dynamodb_table              = "tflock"
access_key                  = "test"
secret_key                  = "test"
use_path_style              = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_s3_checksum            = true
endpoints = {
  s3       = "http://localhost:4566"
  dynamodb = "http://localhost:4566"
}
