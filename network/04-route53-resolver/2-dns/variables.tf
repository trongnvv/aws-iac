variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Static private IP of the simulated on-prem DNS server (dnsmasq), created in layer 3-onprem-dns.
# Hardcoded here to break the chicken-and-egg: the outbound forwarding rule (corp.local → on-prem DNS)
# needs this target IP, but the on-prem host is built AFTER this layer. We pin the IP in the on-prem
# subnet (192.168.0.0/24) so it is known in advance; layer 3 launches the host at exactly this IP.
variable "onprem_dns_ip" { default = "192.168.0.53" }
