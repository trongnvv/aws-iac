variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# Pin the AWS Load Balancer Controller IAM policy to the chart version installed
# in layer1/02. Keep in sync with the Helm chart's appVersion.
variable "lbc_policy_version" {
  default = "v2.11.0"
}

# Secret path prefix External Secrets Operator is allowed to read (least priv).
variable "eso_secret_path" {
  default = "prod/*"
}

# Wired from the eks module output by the env root.
variable "cluster_name" {
  type = string
}
