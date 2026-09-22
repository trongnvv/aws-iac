terraform {
  required_version = ">= 1.9.0"

  backend "local" {
    path = "terraform.tfstate"
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
  backend = "local"
  config = {
    path = "../00-network/terraform.tfstate"
  }
}

locals {
  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  app_subnet_ids = data.terraform_remote_state.network.outputs.app_subnet_ids
}
