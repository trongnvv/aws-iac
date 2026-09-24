terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket         = "eks-iac-tfstate"
    key            = "dev/layer0/05-security-baseline/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "eks-iac-tflock"
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = "ap-southeast-1"
  profile = "default"
}

# Account-level security singletons stay OFF in dev — prod owns them (one per account).
module "security_baseline" {
  source = "../../../modules/security-baseline"
  env    = "dev"
  region = "ap-southeast-1"
}
