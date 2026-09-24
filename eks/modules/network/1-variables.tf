variable "region" {
  default = "ap-southeast-1"
}

# Environment / system name — isolates state (key prefix) and prefixes
# global-unique names so a second system doesn't collide.
variable "env" {
  default = "dev"
}

# Tags resources + sets the karpenter.sh/discovery value on app subnets.
variable "cluster_name" {
  default = "eks-dev"
}

# /16: the VPC CNI assigns one VPC IP per pod, and CIDR can't be resized later.
# All subnet CIDRs are derived from this (see 2-vpc.tf), so a whole env moves to a
# non-overlapping range by setting just this one knob per env (peering/TGW-safe).
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "azs" {
  default = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}

# false = one shared NAT (~$0.05/h); true = one per AZ (failover, pricier).
variable "nat_per_az" {
  default = false
}

# Secondary CIDR for pod IPs (VPC CNI custom networking) — off by default.
# Pod subnets are derived from this block.
variable "enable_secondary_cidr" {
  default = false
}

variable "secondary_cidr_block" {
  default = "100.64.0.0/16"
}

# Centralized egress inspection (AWS Network Firewall). Expensive (~$285/mo/endpoint)
# → off by default. When on, app egress is redirected: app → firewall endpoint → NAT.
variable "enable_network_firewall" {
  default = false
}

variable "allowed_domains" {
  default = [".amazonaws.com", ".pkg.dev"]
}
