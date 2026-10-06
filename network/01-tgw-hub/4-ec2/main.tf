terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/4-ec2/terraform.tfstate"
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

variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "ssm" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/3-ssm/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed test host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
  sg_ids     = data.terraform_remote_state.vpc.outputs.sg_ids
}

resource "aws_instance" "test" {
  for_each               = local.subnet_ids
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = each.value
  vpc_security_group_ids = [local.sg_ids[each.key]]
  iam_instance_profile   = data.terraform_remote_state.ssm.outputs.instance_profile_name
  tags                   = { Name = "net-lab-${each.key}" }
}

output "instances" {
  description = "Per-VPC test instance: id + private IP (ping these across the TGW)."
  value       = { for k, i in aws_instance.test : k => { id = i.id, private_ip = i.private_ip } }
}
