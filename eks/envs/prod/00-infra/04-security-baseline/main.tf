terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "prod/layer0/04-security-baseline/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = "ap-southeast-1"
  profile = "default"
}

# Account-level security singletons (GuardDuty/Security Hub/Config) — enable in exactly one env per account.
module "security_baseline" {
  source             = "../../../../modules/security-baseline"
  env                = "prod"
  region             = "ap-southeast-1"
  enable_guardduty   = true
  enable_cloudtrail  = true
  enable_config      = true
  enable_securityhub = true
}
