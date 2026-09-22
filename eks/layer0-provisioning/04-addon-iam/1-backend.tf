terraform {
  required_version = ">= 1.9.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    http = { source = "hashicorp/http", version = "~> 3.4" } # fetch LBC IAM policy JSON
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

data "terraform_remote_state" "eks" {
  backend = "local"
  config = {
    path = "../01-eks/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}
