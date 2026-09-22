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

# API endpoint access — toggle per env. Public on = lab-friendly; a locked-down
# env sets public=false + private=true (reach the API via bastion/VPN/SSM).
variable "cluster_endpoint_public_access" {
  default = true
}

variable "cluster_endpoint_private_access" {
  default = true
}

# Lock to your IP (["<YOUR_IP>/32"]). 0.0.0.0/0 leaves the endpoint reachable
# by anyone (still authenticated, but open).
variable "endpoint_public_access_cidrs" {
  default = ["0.0.0.0/0"]
}

# Stream control-plane logs (audit trail) to CloudWatch. Off by default —
# CloudWatch ingest costs money; enable per-env (tfvars) where you need the audit trail.
variable "enable_control_plane_logging" {
  default = false
}

variable "control_plane_log_types" {
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# Envelope-encrypt Kubernetes Secrets in etcd with a KMS key the module creates.
# Off by default — KMS key ~$1/mo; enable in regulated/prod env (tfvars).
variable "enable_secret_encryption" {
  default = false
}

# /28 prefixes instead of single IPs → ~110 pods on an m5.large vs ~29.
variable "enable_prefix_delegation" {
  default = true
}

# Security groups per pod (ENABLE_POD_ENI) — e.g. only some pods may reach RDS.
variable "enable_pod_eni" {
  default = false
}

# VPC CNI network-policy enforcement (needed for layer1/07-network-policy).
variable "enable_network_policy" {
  default = false
}

# EFS CSI driver as a managed add-on (RWX volumes). Driver is free; EFS storage costs.
variable "enable_efs_csi" {
  default = false
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
