variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# WAF bills per web ACL + rule + request → default off; enable per-env.
variable "enable_waf" {
  default = false
}

variable "web_acl_name" {
  default = "eks-alb-waf"
}
