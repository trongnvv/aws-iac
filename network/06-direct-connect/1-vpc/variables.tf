variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Two VPCs, non-overlapping:
#   aws    = the cloud VPC reached from on-prem via the DX Gateway → TGW (10.30.0.0/16).
#   onprem = a VPC that SIMULATES the on-prem data center (192.168.30.0/16). The strongSwan EC2
#            living in it plays the Customer Gateway / on-prem router. 192.168.30/16 is deliberately
#            far from 10/8 so the BGP-advertised prefix never overlaps the cloud side, and distinct
#            from lab 2's 192.168.0.0/16 so the two labs can coexist.
locals {
  vpcs = {
    aws    = "10.30.0.0/16"
    onprem = "192.168.30.0/16"
  }
}

data "aws_availability_zones" "available" { state = "available" }
