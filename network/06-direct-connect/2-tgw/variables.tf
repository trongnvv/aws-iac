variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Amazon-side BGP ASN for the TGW. The VPN connection (4-vpn, the transport stand-in) peers the on-prem
# FRR (ASN 65000) against this. The DX Gateway (3-dxgw) carries its OWN amazon-side ASN (a separate
# BGP domain between the Transit VIF and the DX Gateway) — see 3-dxgw/variables.tf. 64512 is the start
# of the private-ASN range and AWS's common default.
variable "amazon_side_asn" { default = 64512 }
