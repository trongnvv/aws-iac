variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Tags resources + sets the karpenter.sh/discovery value on app subnets.
variable "cluster_name" {
  default = "eks-dev"
}

# /16: the VPC CNI assigns one VPC IP per pod, and CIDR can't be resized later.
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

# app subnets are /20 (4k IPs) for EKS pods; isolated /24 for DBs/caches.
variable "public_subnet_cidrs" {
  default = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "app_subnet_cidrs" {
  default = ["10.0.48.0/20", "10.0.64.0/20", "10.0.80.0/20"]
}

variable "isolated_subnet_cidrs" {
  default = ["10.0.96.0/24", "10.0.97.0/24", "10.0.98.0/24"]
}
