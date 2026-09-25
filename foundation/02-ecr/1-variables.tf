variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Shared registry — one image built once, promoted (same digest) across all envs.
# Repo names are NOT env-prefixed (that's the whole point of a shared ECR).
variable "repo_names" {
  default = ["app"]
}

# Enhanced scanning uses Amazon Inspector (bills per scan) → default off.
variable "enable_enhanced_scan" {
  default = false
}
