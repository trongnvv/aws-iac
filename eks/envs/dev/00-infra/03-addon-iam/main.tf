terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/03-addon-iam/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    http = { source = "hashicorp/http", version = "~> 3.4" }
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

module "addon_iam" {
  source       = "../../../../modules/addon-iam"
  region       = "ap-southeast-1"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}

output "lbc_role_arn" { value = module.addon_iam.lbc_role_arn }
output "eso_role_arn" { value = module.addon_iam.eso_role_arn }
output "external_dns_role_arn" { value = module.addon_iam.external_dns_role_arn }
output "keda_role_arn" { value = module.addon_iam.keda_role_arn }
output "cert_manager_role_arn" { value = module.addon_iam.cert_manager_role_arn }
output "kubecost_role_arn" { value = module.addon_iam.kubecost_role_arn }
