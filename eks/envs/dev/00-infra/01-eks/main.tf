terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/01-eks/terraform.tfstate"
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

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "dev/layer0/00-network/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

module "eks" {
  source         = "../../../../modules/eks"
  env            = "dev"
  cluster_name   = "eks-dev"
  region         = "ap-southeast-1"
  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  app_subnet_ids = data.terraform_remote_state.network.outputs.app_subnet_ids

  # SSO permission-set role(s) that need K8s access in the console (fixes "Unauthorized").
  # Get the role ARN: AWS console shows the assumed-role; map it to the underlying
  # AWSReservedSSO_* role ARN. Leave empty = only the cluster creator has admin.
  admin_principal_arns = [
    "arn:aws:iam::391511533175:root",
  ]
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_version" { value = module.eks.cluster_version }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "node_security_group_id" { value = module.eks.node_security_group_id }
output "cluster_security_group_id" { value = module.eks.cluster_security_group_id }
