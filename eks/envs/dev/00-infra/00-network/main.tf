terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/00-network/terraform.tfstate"
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

module "network" {
  source       = "../../../../modules/network"
  env          = "dev"
  cluster_name = "eks-dev"
  region       = "ap-southeast-1"
}

output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "app_subnet_ids" { value = module.network.app_subnet_ids }
output "isolated_subnet_ids" { value = module.network.isolated_subnet_ids }
output "nat_public_ips" { value = module.network.nat_public_ips }
