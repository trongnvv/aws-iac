variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# OPTIONAL — off by default (segmentation lab 1 stays NAT-free/cheap). Turn on to add centralized
# egress: spokes reach the internet via ONE NAT in the shared VPC, through the TGW.
#   enable with: tofu apply -var enable_egress=true
variable "enable_egress" { default = false }
