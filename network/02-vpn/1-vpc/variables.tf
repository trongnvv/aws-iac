variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Two VPCs, non-overlapping:
#   aws    = the cloud VPC that terminates the VPN on the TGW (10.10.0.0/16).
#   onprem = a VPC that SIMULATES the on-prem data center (192.168.0.0/16). The strongSwan EC2
#            living in it plays the Customer Gateway. 192.168/16 is deliberately far from 10/8 so
#            BGP-advertised prefixes never overlap the cloud side.
locals {
  vpcs = {
    aws    = "10.10.0.0/16"
    onprem = "192.168.0.0/16"
  }
}

data "aws_availability_zones" "available" { state = "available" }
