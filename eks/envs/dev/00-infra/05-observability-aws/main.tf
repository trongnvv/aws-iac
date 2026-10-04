terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/05-observability-aws/terraform.tfstate"
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
  source       = "../../../../modules/observability-aws"
  env          = "dev"
  region       = "ap-southeast-1"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  # AWS-native observability, Prometheus flavor (test-plans/03 Part A). The AMP workspace
  # survives teardown.sh (only the IAM roles are destroyed) so its ID — hardcoded in the
  # 02-platform values — stays stable across redeploys.
  enable_amp                 = true
  enable_aws_native_pipeline = true
}

output "amp_workspace_arn" { value = module.observability_aws.amp_workspace_arn }
output "amp_remote_write_url" { value = module.observability_aws.amp_remote_write_url }
output "amp_endpoint" { value = module.observability_aws.amp_endpoint }
