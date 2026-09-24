terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/06-observability-aws/terraform.tfstate"
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

module "observability_aws" {
  source       = "../../../modules/observability-aws"
  env          = "dev"
  region       = "ap-southeast-1"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}

output "amp_workspace_arn" { value = module.observability_aws.amp_workspace_arn }
output "amp_remote_write_url" { value = module.observability_aws.amp_remote_write_url }
