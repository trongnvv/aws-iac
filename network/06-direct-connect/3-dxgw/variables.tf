variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Amazon-side BGP ASN for the DX GATEWAY. This is the ASN the DX Gateway uses when peering BGP with the
# customer router over the Transit VIF (a SEPARATE BGP domain from the TGW's amazon_side_asn in 2-tgw).
# Keep it distinct from the TGW ASN (64512) to make the two control planes obvious. 64513 is private.
variable "dxgw_amazon_side_asn" { default = 64513 }
