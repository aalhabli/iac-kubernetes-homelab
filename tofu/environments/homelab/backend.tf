terraform {
  backend "s3" {
    bucket = "tofu-state-homelab"
    key    = "homelab/terraform.tfstate"
    region = "us-east-1"

    # MinIO endpoint on the workstation, over the LAN (ADR-0011). Resolved by
    # a PiHole local DNS record so the endpoint survives the host moving or
    # being reassigned an address. Named for the service rather than the host,
    # so Longhorn, PBS and Velero can share it and MinIO can relocate later.
    endpoints = { s3 = "http://minio.lab.alhabli.com:9000" }

    # MinIO requires path-style routing instead of virtual host-style routing
    use_path_style = true

    # Skip AWS-specific validations since we are using MinIO
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
