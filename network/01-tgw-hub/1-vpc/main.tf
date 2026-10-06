terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/1-vpc/terraform.tfstate"
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

# shared = hub, prod/dev = spokes. Non-overlapping /16s.
locals {
  vpcs = {
    shared = "10.0.0.0/16"
    prod   = "10.1.0.0/16"
    dev    = "10.2.0.0/16"
  }
}

data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  tags                 = { Name = "net-lab-${each.key}" }
}

resource "aws_subnet" "this" {
  for_each                = local.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(each.value, 8, 0) # 10.x.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-${each.key}-public" }
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-${each.key}" }
}

# Internet via IGW (for SSM). The cross-VPC route (10/8 → TGW) is added by layer 2-tgw.
resource "aws_route" "igw" {
  for_each               = local.vpcs
  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.key].id
}

resource "aws_route_table_association" "this" {
  for_each       = local.vpcs
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

# ICMP from any lab VPC → lets us ping across the TGW. SSM needs no inbound rule.
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  ingress {
    description = "ICMP from lab VPCs"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-${each.key}" }
}

output "vpc_ids" { value = { for k, v in aws_vpc.this : k => v.id } }
output "subnet_ids" { value = { for k, s in aws_subnet.this : k => s.id } }
output "sg_ids" { value = { for k, s in aws_security_group.this : k => s.id } }
output "route_table_ids" { value = { for k, r in aws_route_table.this : k => r.id } }
output "vpc_cidrs" { value = local.vpcs }
