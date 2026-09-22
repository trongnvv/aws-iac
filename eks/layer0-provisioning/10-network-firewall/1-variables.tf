variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# AWS Network Firewall is expensive (~$285/mo/endpoint + data) → default off.
variable "enable_network_firewall" {
  default = false
}

# Egress allowlist — only these domains are reachable outbound when enabled.
variable "allowed_domains" {
  default = [".amazonaws.com", ".pkg.dev"]
}
