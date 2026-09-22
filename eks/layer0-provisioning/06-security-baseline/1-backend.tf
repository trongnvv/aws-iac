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

data "aws_caller_identity" "current" {}
