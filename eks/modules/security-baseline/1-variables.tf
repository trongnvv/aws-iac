variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# Account-level security services — each bills with usage → all default off.
# ⚠️ GuardDuty detector, Security Hub, and the Config recorder are ONE-per-account/
# region singletons: enable them in exactly ONE env per account (e.g. prod owns them),
# else a second env's apply fails with "already exists".
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
