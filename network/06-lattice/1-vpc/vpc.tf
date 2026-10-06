resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  # DNS resolution MUST be on: clients resolve the Lattice service DNS name via the VPC resolver,
  # which Lattice hijacks for the link-local 169.254.171.x data path once the VPC is associated.
  enable_dns_support = true
  tags               = { Name = "net-lab-lattice-${each.key}" }
}

resource "aws_subnet" "this" {
  for_each                = local.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(each.value, 8, 0) # 10.0.0.0/24 in BOTH VPCs (overlap)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-lattice-${each.key}-public" }
}

# IGW only so the SSM agent can reach AWS (management plane). Lattice traffic never uses it —
# it goes to the link-local Lattice endpoint inside the VPC, not out to the internet.
resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-lattice-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-lattice-${each.key}" }
}

# 0/0 → IGW for SSM only. NOTE: there is deliberately NO route between VPC A and VPC B — no peering,
# no TGW. The only thing that lets A reach B is the Lattice service network (layer 2 + 3).
resource "aws_route" "igw" {
  for_each               = local.vpcs
  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.key].id
}

resource "aws_route_table_association" "this" {
  for_each       = local.vpcs
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}
