resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  tags                 = { Name = "net-lab-dx-${each.key}" }
}

# One public subnet per VPC. The aws test host and the onprem strongSwan appliance both sit here so
# their SSM agents reach AWS directly over the IGW (no NAT / VPC endpoints needed).
resource "aws_subnet" "this" {
  for_each                = local.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(each.value, 8, 0) # 10.30.0.0/24 · 192.168.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-dx-${each.key}-public" }
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-dx-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-dx-${each.key}" }
}

# Internet via IGW (for SSM + the IPsec endpoint — the VPN transport stand-in — to reach AWS's public
# tunnel IPs). The cross-site routes — aws: 192.168/16 → TGW (added by 2-tgw); onprem: 10.30/16 →
# strongSwan ENI (added by 5-strongswan) — are layered on later.
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
