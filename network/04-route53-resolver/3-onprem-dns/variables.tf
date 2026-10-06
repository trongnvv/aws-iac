variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# MUST match var.onprem_dns_ip in layer 2-dns (the outbound forwarding-rule target). The host is
# launched at this exact private IP so the rule target is correct before this host even exists.
variable "onprem_dns_ip" { default = "192.168.0.53" }
