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
