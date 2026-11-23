variable "region" { default = "ap-southeast-1" }  # home — where Lab 1's existing TGW lives
variable "region2" { default = "ap-northeast-1" } # new region for this layer's own VPC + TGW
variable "profile" { default = "default" }

# OPTIONAL — off by default, same convention as 5-egress. Turn on to add a second region's
# VPC + TGW, peered to Lab 1's hub via a TGW Peering attachment (static routes, not propagated).
#   enable with: tofu apply -var enable_peering=true
variable "enable_peering" { default = false }

# Distinct from Lab 1's 10.0/10.1/10.2.0.0/16 (shared/prod/dev) but still inside the same
# 10.0.0.0/8 "net-lab" supernet — Lab 1's existing shared-VPC subnet route (10.0.0.0/8 → TGW,
# from 1-vpc) already covers it, so no change needed on that side at the VPC-subnet level.
variable "region2_cidr" { default = "10.99.0.0/16" }
