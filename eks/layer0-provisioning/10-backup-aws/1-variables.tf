variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Backup storage + EBS snapshots cost money → default off; enable per-env.
variable "enable_backup" {
  default = false
}

# Globally-unique bucket for Velero backups.
variable "backup_bucket_name" {
  default = "eks-velero-backups"
}

# namespace + service account of the Velero release (layer2 chart).
variable "velero_namespace" {
  default = "velero"
}

variable "velero_service_account" {
  default = "velero"
}
