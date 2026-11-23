terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/6-region2-peering/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

# Second region's TGW/VPC/EC2 all live here — a peering attachment is created from the
# requester's region (var.region) but accepted from the peer's region (var.region2).
provider "aws" {
  alias   = "region2"
  region  = var.region2
  profile = var.profile
}
