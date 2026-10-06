variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Amazon-side BGP ASN for the TGW. The VPN connection (3-vpn) peers the on-prem FRR (ASN 65000)
# against this. 64512 is the start of the private-ASN range and AWS's common default.
variable "amazon_side_asn" { default = 64512 }
