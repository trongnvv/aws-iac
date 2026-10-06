resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  tags                 = { Name = "net-lab-${each.key}" }
}

resource "aws_subnet" "this" {
  for_each                = local.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(each.value, 8, 0) # 10.x.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-${each.key}-public" }
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-${each.key}" }
}

# Internet via IGW (for SSM). The cross-VPC route (10/8 → TGW) is added by layer 2-tgw.
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

# Dedicated subnet for the shared VPC's TGW attachment — makes the lab egress-ready: 5-egress can
# route 0/0 from the attachment to the central NAT without touching the public subnet (which keeps
# 0/0 → IGW for SSM). Free (no NAT here); harmless when egress is off.
resource "aws_subnet" "shared_tgw" {
  vpc_id            = aws_vpc.this["shared"].id
  cidr_block        = cidrsubnet(local.vpcs["shared"], 8, 255) # 10.0.255.0/24
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "net-lab-shared-tgw" }
}

resource "aws_route_table" "shared_tgw" {
  vpc_id = aws_vpc.this["shared"].id
  tags   = { Name = "net-lab-shared-tgw" }
}

resource "aws_route_table_association" "shared_tgw" {
  subnet_id      = aws_subnet.shared_tgw.id
  route_table_id = aws_route_table.shared_tgw.id
}
