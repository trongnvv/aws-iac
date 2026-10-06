resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  enable_dns_support   = true # resolver endpoints + PHZ need VPC DNS on
  tags                 = { Name = "net-lab-r53-${each.key}" }
}

# ── AWS VPC subnets: 2 AZs (resolver endpoints want 2) ───────────────────────
resource "aws_subnet" "aws" {
  for_each                = toset(["a", "b"])
  vpc_id                  = aws_vpc.this["aws"].id
  cidr_block              = cidrsubnet(local.aws_cidr, 8, each.key == "a" ? 0 : 1) # 10.20.0.0/24, 10.20.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[each.key == "a" ? 0 : 1]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-r53-aws-public-${each.key}" }
}

# ── On-prem VPC subnet: 1 AZ (just the DNS server + a test host) ──────────────
resource "aws_subnet" "onprem" {
  vpc_id                  = aws_vpc.this["onprem"].id
  cidr_block              = cidrsubnet(local.onprem_cidr, 8, 0) # 192.168.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-r53-onprem-public" }
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-r53-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-r53-${each.key}" }
}

# Internet via IGW — needed so the SSM agent reaches AWS (public subnet pattern, no NAT/endpoints).
resource "aws_route" "igw" {
  for_each               = local.vpcs
  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.key].id
}

# ── VPC Peering aws ↔ onprem: carries the actual DNS query packets ───────────
# AWS→on-prem: outbound endpoint ENI (in aws VPC) → on-prem DNS server (192.168.x) → needs a route.
# on-prem→AWS: on-prem DNS server → inbound endpoint ENI (10.20.x)                  → needs a route.
# The peering is what makes those forwarded queries reachable. (A real site would use VPN/DX here.)
resource "aws_vpc_peering_connection" "this" {
  vpc_id      = aws_vpc.this["aws"].id
  peer_vpc_id = aws_vpc.this["onprem"].id
  auto_accept = true # same account + region → accept inline, no separate accepter resource
  tags        = { Name = "net-lab-r53-aws-onprem" }
}

resource "aws_route" "aws_to_onprem" {
  route_table_id            = aws_route_table.this["aws"].id
  destination_cidr_block    = local.onprem_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_route" "onprem_to_aws" {
  route_table_id            = aws_route_table.this["onprem"].id
  destination_cidr_block    = local.aws_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# ── Route table associations ─────────────────────────────────────────────────
resource "aws_route_table_association" "aws" {
  for_each       = aws_subnet.aws
  subnet_id      = each.value.id
  route_table_id = aws_route_table.this["aws"].id
}

resource "aws_route_table_association" "onprem" {
  subnet_id      = aws_subnet.onprem.id
  route_table_id = aws_route_table.this["onprem"].id
}
