variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# On-prem BGP ASN — the FRR daemon on the strongSwan appliance peers with this ASN. The customer
# gateway declares it to AWS; the amazon-side ASN (64512) comes from the TGW (2-tgw).
variable "onprem_bgp_asn" { default = 65000 }
