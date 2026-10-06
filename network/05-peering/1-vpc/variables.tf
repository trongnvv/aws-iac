variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# A = hub (peers with both B and C). B and C are NOT peered with each other → that's the
# whole point: proving VPC peering is non-transitive. Non-overlapping /16s.
locals {
  vpcs = {
    a = "10.0.0.0/16"
    b = "10.1.0.0/16"
    c = "10.2.0.0/16"
  }
}

data "aws_availability_zones" "available" { state = "available" }
