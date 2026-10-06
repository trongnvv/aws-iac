# Two peering connections, both hub-and-spoke around A: A↔B and A↔C. B and C are NEVER peered.
# Same account + same region → auto_accept = true (no separate accepter / cross-account handshake).
resource "aws_vpc_peering_connection" "a_b" {
  vpc_id      = local.vpc_ids["a"]
  peer_vpc_id = local.vpc_ids["b"]
  auto_accept = true
  tags        = { Name = "net-lab-peer-a-b" }
}

resource "aws_vpc_peering_connection" "a_c" {
  vpc_id      = local.vpc_ids["a"]
  peer_vpc_id = local.vpc_ids["c"]
  auto_accept = true
  tags        = { Name = "net-lab-peer-a-c" }
}

# ---- Routes ----
# Peering is only data-plane once BOTH sides have a route pointing the peer's CIDR at the pcx.
# A's route table learns BOTH peers (A is the hub) ...
resource "aws_route" "a_to_b" {
  route_table_id            = local.rt_ids["a"]
  destination_cidr_block    = local.cidrs["b"]
  vpc_peering_connection_id = aws_vpc_peering_connection.a_b.id
}

resource "aws_route" "a_to_c" {
  route_table_id            = local.rt_ids["a"]
  destination_cidr_block    = local.cidrs["c"]
  vpc_peering_connection_id = aws_vpc_peering_connection.a_c.id
}

# ... B learns ONLY A ...
resource "aws_route" "b_to_a" {
  route_table_id            = local.rt_ids["b"]
  destination_cidr_block    = local.cidrs["a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.a_b.id
}

# ... C learns ONLY A.
resource "aws_route" "c_to_a" {
  route_table_id            = local.rt_ids["c"]
  destination_cidr_block    = local.cidrs["a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.a_c.id
}

# DELIBERATELY ABSENT: no route for B→C or C→B, and no B↔C peering connection.
# Even though B and A are peered, and A and C are peered, B cannot reach C *through* A —
# VPC peering is NON-TRANSITIVE. A packet B→C has no route in B, and even if forced, A would
# not forward it across a second pcx. This is the lab's core proof (contrast Lab 1's TGW,
# which IS transitive).
