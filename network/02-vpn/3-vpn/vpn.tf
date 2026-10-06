# ── EIP for the strongSwan appliance (the Customer Gateway's public IP) ─────────────────────────
# Allocated HERE, not in 4-strongswan, to break the chicken-and-egg: the customer gateway must know
# the appliance's public IP, while the appliance's user_data must know the VPN tunnel addresses/PSKs.
# Allocating the EIP first lets 3-vpn build the CGW + VPN connection from a known IP; 4-strongswan
# then associates this same EIP to the instance it creates.
resource "aws_eip" "strongswan" {
  domain = "vpc"
  tags   = { Name = "net-lab-vpn-strongswan" }
}

# Customer Gateway = AWS's record of the on-prem peer: its public IP (the EIP above) and BGP ASN.
# type ipsec.1 + bgp_asn makes this a DYNAMIC (BGP) VPN, not static.
resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.onprem_bgp_asn
  ip_address = aws_eip.strongswan.public_ip
  type       = "ipsec.1"
  tags       = { Name = "net-lab-vpn-onprem" }
}

# The Site-to-Site VPN itself, terminating on the TGW (not a VGW). AWS builds TWO tunnels for HA, each
# with its own outside (public) endpoint, inside /30 (APIPA 169.254.x.x) link, and PSK. Leaving the
# tunnel options unset lets AWS auto-generate the PSKs + inside CIDRs; 4-strongswan reads them back
# from this resource's attributes and injects them into strongSwan/FRR config.
resource "aws_vpn_connection" "this" {
  customer_gateway_id = aws_customer_gateway.onprem.id
  transit_gateway_id  = local.tgw_id
  type                = "ipsec.1"
  # DYNAMIC routing (BGP). static_routes_only=false is the default for a BGP CGW, set explicit for clarity.
  static_routes_only = false
  tags               = { Name = "net-lab-vpn" }
}

# ── TGW route-table wiring for the VPN attachment ──────────────────────────────────────────────
# A TGW VPN attachment is created implicitly by aws_vpn_connection when transit_gateway_id is set.
# Grab its id so we can associate it to the main RT and propagate the BGP-learned on-prem prefix.
resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  transit_gateway_attachment_id  = aws_vpn_connection.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = local.tgw_rt_id
}

# Propagate routes LEARNED over the VPN (via BGP from FRR — i.e. 192.168/16) into the main RT, so the
# aws VPC attachment can reach on-prem through the TGW.
resource "aws_ec2_transit_gateway_route_table_propagation" "vpn" {
  transit_gateway_attachment_id  = aws_vpn_connection.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = local.tgw_rt_id
}
