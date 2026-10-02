terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "foundation/app-cicd/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
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

# Reuse the GitLab CodeConnections connection created in 03-cicd (already authorized).
data "terraform_remote_state" "cicd" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "foundation/cicd/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  account  = data.aws_caller_identity.current.account_id
  conn_arn = data.terraform_remote_state.cicd.outputs.gitlab_connection_arn
  grpc_arn = "arn:aws:ecr:${var.region}:${local.account}:repository/grpc-conn-debug/*"
  logs_arn = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/codebuild/grpc-conn-debug-build*"
}
