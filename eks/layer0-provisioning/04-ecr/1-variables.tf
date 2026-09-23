variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

variable "env" {
  default = "dev"
}

variable "repo_names" {
  default = ["app"]
}

# Enhanced scanning uses Amazon Inspector, which bills per scan → default off.
# Basic scan-on-push (below) is free and always on.
variable "enable_enhanced_scan" {
  default = false
}
