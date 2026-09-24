variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# Backup storage + EBS snapshots cost money → default off; enable per-env.
variable "enable_backup" {
  default = false
}

# Globally-unique bucket for Velero backups.
variable "velero_bucket_name" {
  default = "eks-velero-backups"
}

# namespace + service account of the Velero release (layer2 chart).
variable "velero_namespace" {
  default = "velero"
}

variable "velero_service_account" {
  default = "velero"
}

# Wired from the eks module output by the env root.
variable "cluster_name" {
  type = string
}
