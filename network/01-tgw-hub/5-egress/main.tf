terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/5-egress/terraform.tfstate"
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

# OPTIONAL — off by default (segmentation lab 1 stays NAT-free/cheap). Turn on to add centralized
# egress: spokes reach the internet via ONE NAT in the shared VPC, through the TGW.
#   enable with: tofu apply -var enable_egress=true
variable "enable_egress" { default = false }

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}
data "terraform_remote_state" "tgw" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/2-tgw/terraform.tfstate", region = "ap-southeast-1" }
}
data "terraform_remote_state" "ssm" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/3-ssm/terraform.tfstate", region = "ap-southeast-1" }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}
data "aws_availability_zones" "available" { state = "available" }

locals {
  on     = var.enable_egress
  spokes = local.on ? toset(["prod", "dev"]) : toset([])

  vo                = data.terraform_remote_state.vpc.outputs
  shared_public_sub = local.vo.subnet_ids["shared"]
  shared_tgw_rt     = local.vo.shared_tgw_route_table_id
  tgw_id            = data.terraform_remote_state.tgw.outputs.tgw_id
  spoke_tgw_rt      = data.terraform_remote_state.tgw.outputs.spoke_route_table_id
  shared_attach     = data.terraform_remote_state.tgw.outputs.shared_attachment_id
}

# ── NAT in the shared VPC (public subnet) ────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.on ? 1 : 0
  domain = "vpc"
  tags   = { Name = "net-lab-egress" }
}

resource "aws_nat_gateway" "this" {
  count         = local.on ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.shared_public_sub
  tags          = { Name = "net-lab-egress" }
}

# Return path: traffic arriving from spokes at the shared TGW-attachment subnet → NAT.
resource "aws_route" "shared_tgw_to_nat" {
  count                  = local.on ? 1 : 0
  route_table_id         = local.shared_tgw_rt
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# TGW spoke route table: default route → shared attachment (so spokes send 0/0 to the hub).
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  count                          = local.on ? 1 : 0
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = local.shared_attach
  transit_gateway_route_table_id = local.spoke_tgw_rt
}

# ── Spoke private subnets — no IGW; internet only via the central NAT (proves egress) ─────────
resource "aws_subnet" "private" {
  for_each          = local.spokes
  vpc_id            = local.vo.vpc_ids[each.key]
  cidr_block        = cidrsubnet(local.vo.vpc_cidrs[each.key], 8, 100) # 10.x.100.0/24
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "net-lab-${each.key}-private" }
}

resource "aws_route_table" "private" {
  for_each = local.spokes
  vpc_id   = local.vo.vpc_ids[each.key]
  tags     = { Name = "net-lab-${each.key}-private" }
}

resource "aws_route" "private_default" {
  for_each               = local.spokes
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.tgw_id
}

resource "aws_route_table_association" "private" {
  for_each       = local.spokes
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Private test host — no public IP; its SSM agent + any curl reaches the internet via the shared NAT.
resource "aws_instance" "private" {
  for_each               = local.spokes
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = aws_subnet.private[each.key].id
  vpc_security_group_ids = [local.vo.sg_ids[each.key]]
  iam_instance_profile   = data.terraform_remote_state.ssm.outputs.instance_profile_name
  tags                   = { Name = "net-lab-${each.key}-private" }
}

output "egress_enabled" { value = local.on }
output "nat_public_ip" { value = local.on ? aws_eip.nat[0].public_ip : null }
output "private_instances" {
  value = { for k, i in aws_instance.private : k => { id = i.id, private_ip = i.private_ip } }
}
