variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Two VPCs: the AWS side and a simulated on-prem. Non-overlapping CIDRs so a VPC peering can route
# DNS queries both ways (overlap would break routing — not the point of this lab).
locals {
  aws_cidr    = "10.20.0.0/16"
  onprem_cidr = "192.168.0.0/16"

  # Resolver endpoints (inbound + outbound) require ENIs in 2 AZs → the AWS VPC needs 2 subnets.
  # On-prem is a single DNS host, 1 subnet is enough.
  vpcs = {
    aws    = "10.20.0.0/16"
    onprem = "192.168.0.0/16"
  }
}

data "aws_availability_zones" "available" { state = "available" }
