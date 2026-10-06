terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/2-tgw/terraform.tfstate"
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
  config = {
    bucket = "network-iac-tfstate"
    key    = "01-tgw-hub/1-vpc/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  vpc_ids    = data.terraform_remote_state.vpc.outputs.vpc_ids
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
  rt_ids     = data.terraform_remote_state.vpc.outputs.route_table_ids
}

# TGW hub. Default route-table assoc/propagation OFF → two custom RTs segment:
#   shared RT learns prod+dev (shared reaches both) · spoke RT learns shared only (prod ⊥ dev).
resource "aws_ec2_transit_gateway" "this" {
  description                     = "net-lab hub"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags                            = { Name = "net-lab" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each                                        = local.vpc_ids
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = each.value
  subnet_ids                                      = [local.subnet_ids[each.key]]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "net-lab-${each.key}" }
}

resource "aws_ec2_transit_gateway_route_table" "shared" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-shared" }
}
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-spoke" }
}

# Associations
resource "aws_ec2_transit_gateway_route_table_association" "shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each                       = toset(["prod", "dev"])
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Propagations
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_learns_spokes" {
  for_each                       = toset(["prod", "dev"])
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_learn_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Cross-VPC route added to each VPC's route table (created in 1-vpc): 10/8 → TGW.
resource "aws_route" "tgw" {
  for_each               = local.rt_ids
  route_table_id         = each.value
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}

output "tgw_id" { value = aws_ec2_transit_gateway.this.id }
