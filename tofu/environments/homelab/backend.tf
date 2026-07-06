terraform {
  backend "s3" {
    bucket = "tofu-state-homelab"
    key = "homelab/terraform.tfstate"
    region = "us-east-1"

    # MinIO endpoint
    endpoints = { s3 = "http://100.83.147.107:9000"}

    # MinIO requires path-style routing instead of virtual host-style routing
    use_path_style = true

    # Skip AWS-specific validations since we are using MinIO
    skip_credentials_validation = true
    skip_region_validation = true
    skip_requesting_account_id = true
    skip_metadata_api_check = true
    skip_s3_checksum = true
  }
}
