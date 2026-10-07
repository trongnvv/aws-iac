# ── The on-prem router appliance (VPN transport stand-in for the Transit VIF) ────────────────────
# A t4g.micro running strongSwan (IPsec, both tunnels) + FRR (BGP). It terminates the two VPN tunnels
# AWS built in 4-vpn and exchanges routes over BGP: advertises 192.168.30/16 to AWS, learns 10.30/16
# back. This is the customer router a real Direct Connect's Transit VIF would BGP-peer with; here it
# dials IPsec over the public internet instead of a physical cross-connect.
#
# source_dest_check MUST be off: the box forwards packets for the onprem test host (src/dst not its own
# IP), which EC2 drops by default with the check on.
resource "aws_instance" "strongswan" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.onprem_subnet_id
  vpc_security_group_ids = [local.strongswan_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  source_dest_check      = false

  # All tunnel addresses/PSKs/ASNs come from the VPN connection (4-vpn) via remote state and are
  # rendered into the setup script below.
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    tunnel1_address    = local.no.tunnel1_address
    tunnel2_address    = local.no.tunnel2_address
    tunnel1_cgw_inside = local.no.tunnel1_cgw_inside
    tunnel1_vgw_inside = local.no.tunnel1_vgw_inside
    tunnel2_cgw_inside = local.no.tunnel2_cgw_inside
    tunnel2_vgw_inside = local.no.tunnel2_vgw_inside
    tunnel1_psk        = local.no.tunnel1_psk
    tunnel2_psk        = local.no.tunnel2_psk
    onprem_bgp_asn     = local.no.onprem_bgp_asn
    amazon_side_asn    = local.no.amazon_side_asn
    aws_cidr           = local.aws_cidr
    onprem_cidr        = local.onprem_cidr
  })
  # Re-render + replace the box if any tunnel parameter changes.
  user_data_replace_on_change = true

  tags = { Name = "net-lab-dx-strongswan" }
}

# Attach the pre-allocated EIP (from 4-vpn — the IP the customer gateway was built with).
resource "aws_eip_association" "strongswan" {
  instance_id   = aws_instance.strongswan.id
  allocation_id = local.no.strongswan_eip_id
}

# onprem VPC → the cloud CIDR (10.30/16) via the strongSwan ENI. This is the on-prem "static route to
# the VPN gateway": the onprem test host sends 10.30/16 to the appliance, which forwards it into the
# tunnel. (The cloud-side return, aws → 192.168.30/16 → TGW, was set in 2-tgw.)
resource "aws_route" "onprem_to_aws" {
  route_table_id         = local.onprem_rt_id
  destination_cidr_block = local.aws_cidr
  network_interface_id   = aws_instance.strongswan.primary_network_interface_id
}
