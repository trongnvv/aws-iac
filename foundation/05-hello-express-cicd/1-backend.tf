terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "foundation/hello-express-cicd/terraform.tfstate"
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

# Reuse the GitLab CodeConnections connection + source credential from 03-cicd (account-level).
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
  ecr_arn  = "arn:aws:ecr:${var.region}:${local.account}:repository/hello-express"
  logs_arn = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/codebuild/hello-express-build*"
}
