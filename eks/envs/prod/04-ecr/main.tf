terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "prod/layer0/04-ecr/terraform.tfstate"
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

module "ecr" {
  source               = "../../../modules/ecr"
  env                  = "prod"
  region               = "ap-southeast-1"
  enable_enhanced_scan = true
}

output "repository_urls" { value = module.ecr.repository_urls }
