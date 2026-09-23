terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    bucket         = "eks-iac-tfstate"
    key            = "layer0/06-observability-aws/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "eks-iac-tflock"
    encrypt        = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "layer0/01-eks/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}
