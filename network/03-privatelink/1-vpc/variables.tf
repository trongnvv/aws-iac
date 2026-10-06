variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# A = provider (exposes the service), B = consumer (reaches it via an interface endpoint).
# BOTH use the SAME CIDR on purpose — PrivateLink doesn't route between the two CIDRs, traffic goes to
# the endpoint ENI inside each VPC, so the overlap is a non-issue. That's the whole point of this lab.
locals {
  vpcs = {
    a = "10.0.0.0/16" # provider
    b = "10.0.0.0/16" # consumer — intentionally identical to prove overlap doesn't matter
  }
}

data "aws_availability_zones" "available" { state = "available" }
