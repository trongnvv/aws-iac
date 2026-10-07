# Consumed by 5-strongswan to build the appliance (EIP to associate) and its strongSwan/FRR config
# (tunnel outside addresses, inside addresses, PSKs, BGP ASNs).
output "vpn_connection_id" { value = aws_vpn_connection.this.id }

output "strongswan_eip_id" { value = aws_eip.strongswan.id }
output "strongswan_eip" { value = aws_eip.strongswan.public_ip }

# Tunnel 1 / 2 OUTSIDE (public) addresses = AWS's VPN endpoints the appliance dials.
output "tunnel1_address" { value = aws_vpn_connection.this.tunnel1_address }
output "tunnel2_address" { value = aws_vpn_connection.this.tunnel2_address }

# INSIDE addresses = the APIPA /30 link per tunnel. cgw_* = on-prem (FRR) side, vgw_* = AWS side.
# FRR peers BGP with the vgw inside address of each tunnel.
output "tunnel1_cgw_inside" { value = aws_vpn_connection.this.tunnel1_cgw_inside_address }
output "tunnel1_vgw_inside" { value = aws_vpn_connection.this.tunnel1_vgw_inside_address }
output "tunnel2_cgw_inside" { value = aws_vpn_connection.this.tunnel2_cgw_inside_address }
output "tunnel2_vgw_inside" { value = aws_vpn_connection.this.tunnel2_vgw_inside_address }

# Pre-shared keys — sensitive. 5-strongswan reads these to write ipsec.secrets.
output "tunnel1_psk" {
  value     = aws_vpn_connection.this.tunnel1_preshared_key
  sensitive = true
}
output "tunnel2_psk" {
  value     = aws_vpn_connection.this.tunnel2_preshared_key
  sensitive = true
}

# BGP ASNs for the FRR config.
output "onprem_bgp_asn" { value = var.onprem_bgp_asn }
output "amazon_side_asn" { value = data.terraform_remote_state.tgw.outputs.amazon_side_asn }
