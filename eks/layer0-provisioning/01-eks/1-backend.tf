terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    bucket         = "eks-iac-tfstate"
    key            = "layer0/01-eks/terraform.tfstate"
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

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "layer0/00-network/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  app_subnet_ids = data.terraform_remote_state.network.outputs.app_subnet_ids
}
