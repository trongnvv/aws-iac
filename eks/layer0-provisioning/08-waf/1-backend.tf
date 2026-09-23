terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    bucket         = "eks-iac-tfstate"
    key            = "layer0/08-waf/terraform.tfstate"
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
