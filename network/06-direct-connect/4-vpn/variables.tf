variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# On-prem BGP ASN — the FRR daemon on the strongSwan appliance peers with this ASN over the VPN
# transport stand-in. The customer gateway declares it to AWS; the amazon-side ASN (64512) comes from
# the TGW (2-tgw). (On a live DX the customer router would also BGP-peer the DX Gateway over the
# Transit VIF — a separate session against the DXGW's ASN in 3-dxgw.)
variable "onprem_bgp_asn" { default = 65000 }
