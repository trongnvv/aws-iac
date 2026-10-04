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

# Wires the rest of the AWS-native pipeline around AMP: kube-prometheus-stack
# Prometheus remote-write, ADOT → X-Ray, Fluent Bit → CloudWatch Logs, and Grafana
# reading AMP/CloudWatch/X-Ray. Requires enable_amp. Pairs with the layer2
# 07-observability-aws release (ADOT + Fluent Bit).
variable "enable_aws_native_pipeline" {
  default = false
}

# Service accounts below must match the Helm releases (kube-prometheus-stack in
# `monitoring`, aws-for-fluent-bit in `logging`).
variable "prometheus_namespace" {
  default = "monitoring"
}

variable "prometheus_service_account" {
  default = "kube-prometheus-stack-prometheus"
}

variable "grafana_service_account" {
  default = "kube-prometheus-stack-grafana"
}

variable "fluent_bit_namespace" {
  default = "logging"
}

variable "fluent_bit_service_account" {
  default = "aws-for-fluent-bit"
}
