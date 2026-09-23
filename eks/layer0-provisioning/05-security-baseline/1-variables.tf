variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Account-level security services — each bills with usage → all default off.
# Enable per-env (tfvars); prod/regulated turns these on.
variable "enable_guardduty" {
  default = false
}

variable "enable_cloudtrail" {
  default = false
}

variable "enable_config" {
  default = false
}

variable "enable_securityhub" {
  default = false
}

# Globally-unique buckets (only created when the matching service is enabled).
variable "cloudtrail_bucket_name" {
  default = "eks-cloudtrail-logs"
}

variable "config_bucket_name" {
  default = "eks-aws-config"
}
