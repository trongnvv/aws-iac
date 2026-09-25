terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/07-waf/terraform.tfstate"
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

module "waf" {
  source = "../../../modules/waf"
  env    = "dev"
  region = "ap-southeast-1"
}

output "web_acl_arn" { value = module.waf.web_acl_arn }
