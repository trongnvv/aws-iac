terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/02-karpenter-infra/terraform.tfstate"
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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "dev/layer0/01-eks/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

module "karpenter_infra" {
  source       = "../../../../modules/karpenter-infra"
  region       = "ap-southeast-1"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}

output "karpenter_queue_name" { value = module.karpenter_infra.karpenter_queue_name }
output "karpenter_node_iam_role_name" { value = module.karpenter_infra.karpenter_node_iam_role_name }
