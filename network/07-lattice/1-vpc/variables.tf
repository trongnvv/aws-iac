variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# A = client VPC, B = service VPC. BOTH use 10.0.0.0/16 on purpose: overlapping CIDR.
# Lattice connects at L7 (HTTP), not L3 — so overlapping address space is a non-issue.
# There is no peering/TGW here, so these two VPCs could never route to each other at L3.
locals {
  vpcs = {
    a = "10.0.0.0/16" # client side
    b = "10.0.0.0/16" # service side — SAME CIDR as A
  }
}

data "aws_availability_zones" "available" { state = "available" }
