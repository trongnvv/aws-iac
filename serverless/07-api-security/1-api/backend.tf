terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "serverless-iac-tfstate"
    key          = "07-api-security/1-api/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}
