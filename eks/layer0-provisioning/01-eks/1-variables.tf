variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

variable "cluster_name" {
  default = "eks-dev"
}

variable "cluster_version" {
  default = "1.32"
}

# Lock to your IP (["<YOUR_IP>/32"]). 0.0.0.0/0 leaves the endpoint reachable
# by anyone (still authenticated, but open).
variable "endpoint_public_access_cidrs" {
  default = ["0.0.0.0/0"]
}

# /28 prefixes instead of single IPs → ~110 pods on an m5.large vs ~29.
variable "enable_prefix_delegation" {
  default = true
}

# Bootstrap "system" node group — hosts core add-ons + Karpenter controller.
# arm64 (Graviton) is cheap; arm64 nodes require arm64 images.
variable "system_instance_types" {
  default = ["t4g.medium"]
}

variable "system_ami_type" {
  default = "AL2023_ARM_64_STANDARD"
}

variable "system_capacity_type" {
  default = "ON_DEMAND"
}

variable "system_min_size" {
  default = 2
}

variable "system_max_size" {
  default = 3
}

variable "system_desired_size" {
  default = 2
}
