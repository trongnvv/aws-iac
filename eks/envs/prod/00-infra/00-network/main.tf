terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "prod/layer0/00-network/terraform.tfstate"
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
  env          = "prod"
  cluster_name = "eks-prod"
  region       = "ap-southeast-1"

  # distinct CIDRs from dev (10.0/16) so the VPCs can peer/TGW without overlap
  vpc_cidr             = "10.1.0.0/16"
  secondary_cidr_block = "100.65.0.0/16"

  nat_per_az              = true
  enable_secondary_cidr   = true
  enable_network_firewall = true
}

output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "app_subnet_ids" { value = module.network.app_subnet_ids }
output "isolated_subnet_ids" { value = module.network.isolated_subnet_ids }
output "nat_public_ips" { value = module.network.nat_public_ips }
