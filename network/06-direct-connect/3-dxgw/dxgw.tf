# =============================================================================================
#  The DX-as-code half — this is the NEW layer vs lab 2 (VPN→TGW).
# =============================================================================================
#  A real Direct Connect needs a PHYSICAL cross-connect at a DX location via a partner, so the
#  aws_dx_connection + the Transit VIF on it cannot be fully provisioned by IaC. What CAN be built as
#  code is the DX control plane that a Transit VIF plugs into:
#
#    DX Gateway  ──(association + allowed_prefixes)──▶  Transit Gateway  ──▶  aws VPC(s)
#
#  - aws_dx_gateway            = a GLOBAL, logical object. A Transit VIF (the one manual step) BGP-peers
#                               with it; the DX Gateway then hands the learned on-prem prefixes to every
#                               associated TGW/VGW. Carries its own amazon-side ASN.
#  - aws_dx_gateway_association = plugs the DX Gateway into THIS lab's TGW, and declares
#                               allowed_prefixes = [on-prem CIDR] — the prefixes the DX Gateway is
#                               allowed to advertise FROM the TGW toward on-prem over the VIF. (For a
#                               TGW association, allowed_prefixes is how the TGW-side CIDRs reach the DX
#                               side — there is no automatic propagation like a VPC/VGW gets.)
#
#  The actual PACKETS in this lab ride the Site-to-Site VPN in 4-vpn (the documented "DX + VPN"
#  transport stand-in). On a live DX the same data path would be the physical Transit VIF instead.
# ---------------------------------------------------------------------------------------------

resource "aws_dx_gateway" "this" {
  name            = "net-lab-dx"
  amazon_side_asn = var.dxgw_amazon_side_asn
}

# Associate the DX Gateway with the TGW. allowed_prefixes = the TGW-side CIDRs the DX Gateway may
# advertise out the Transit VIF toward on-prem. We list the on-prem CIDR as the prefix that the DX
# side is expected to reach (it is also what a live Transit VIF would advertise IN via BGP). This
# creates an implicit TGW attachment of type "direct-connect-gateway".
resource "aws_dx_gateway_association" "tgw" {
  dx_gateway_id         = aws_dx_gateway.this.id
  associated_gateway_id = local.tgw_id

  # The on-prem prefix the DX Gateway ↔ TGW association carries. In a live DX this is learned over the
  # Transit VIF's BGP session; here it documents the intended reachable range.
  allowed_prefixes = [local.onprem_cidr]
}
