variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# AMP bills per sample ingested + stored → default off; enable per-env.
variable "enable_amp" {
  default = false
}

# namespace + service account of the metrics collector (layer2 chart) that
# remote-writes to AMP. Must match the Helm release.
variable "collector_namespace" {
  default = "opentelemetry"
}

variable "collector_service_account" {
  default = "adot-collector"
}

# Wired from the eks module output by the env root.
variable "cluster_name" {
  type = string
}
