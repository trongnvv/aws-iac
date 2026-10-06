resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  tags                 = { Name = "net-lab-pl-${each.key}" }
}

# One public subnet per VPC. Public IP + IGW so the SSM agent reaches AWS without a NAT/endpoints
# (management plane). The service traffic itself never leaves via the IGW — it rides PrivateLink.
resource "aws_subnet" "this" {
  for_each                = local.vpcs
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(each.value, 8, 0) # 10.0.0.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-pl-${each.key}-public" }
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-pl-${each.key}" }
}

resource "aws_route_table" "this" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "net-lab-pl-${each.key}" }
}

# 0/0 → IGW (for SSM). Note there is NO route between A and B — PrivateLink needs none; the consumer
# reaches the service through the endpoint ENI that lives in B's own subnet.
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
