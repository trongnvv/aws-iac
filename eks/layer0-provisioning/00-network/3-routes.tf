resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One app route table per AZ. Default route is a separate aws_route so it can be
# swapped: → NAT normally, or → the firewall endpoint when egress inspection is on
# (see 7-network-firewall.tf for the firewall-path route).
resource "aws_route_table" "app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id
  tags   = { Name = "app-rt-${var.azs[count.index]}" }
}

resource "aws_route" "app_nat" {
  count                  = var.enable_network_firewall ? 0 : length(var.azs)
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[var.nat_per_az ? count.index : 0].id
}

resource "aws_route_table_association" "app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# No default route on purpose — "isolated" means no path to NAT or IGW.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "isolated-rt" }
}

resource "aws_route_table_association" "isolated" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
