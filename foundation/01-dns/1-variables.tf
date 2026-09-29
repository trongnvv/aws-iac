variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Registered domain managed at the registrar; the zone is delegated to Route 53.
variable "domain" {
  type    = string
  default = "trongnv.space"
}
