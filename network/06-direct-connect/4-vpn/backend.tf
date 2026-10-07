terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "06-direct-connect/4-vpn/terraform.tfstate"
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
