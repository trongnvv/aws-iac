# Region 2's own small VPC — one subnet, one test host. Mirrors 1-vpc's shape, just smaller
# (this layer proves peering, not segmentation).
resource "aws_vpc" "region2" {
  count                = local.on ? 1 : 0
  provider             = aws.region2
  cidr_block           = var.region2_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "net-lab-region2" }
}

resource "aws_subnet" "region2" {
  count                   = local.on ? 1 : 0
  provider                = aws.region2
  vpc_id                  = aws_vpc.region2[0].id
  cidr_block              = cidrsubnet(var.region2_cidr, 8, 0)
  availability_zone       = data.aws_availability_zones.region2.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "net-lab-region2-public" }
}

resource "aws_internet_gateway" "region2" {
  count    = local.on ? 1 : 0
  provider = aws.region2
  vpc_id   = aws_vpc.region2[0].id
  tags     = { Name = "net-lab-region2" }
}

resource "aws_route_table" "region2" {
  count    = local.on ? 1 : 0
  provider = aws.region2
  vpc_id   = aws_vpc.region2[0].id
  tags     = { Name = "net-lab-region2" }
}

resource "aws_route" "region2_igw" {
  count                  = local.on ? 1 : 0
  provider               = aws.region2
  route_table_id         = aws_route_table.region2[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.region2[0].id
}

# Same 10.0.0.0/8 catch-all convention as Lab 1's shared VPC → region2's own TGW, so this VPC's
# subnet already knows to send any net-lab address (home region included) to its local TGW.
resource "aws_route" "region2_tgw" {
  count                  = local.on ? 1 : 0
  provider               = aws.region2
  route_table_id         = aws_route_table.region2[0].id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.region2[0].id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.region2]
}

resource "aws_route_table_association" "region2" {
  count          = local.on ? 1 : 0
  provider       = aws.region2
  subnet_id      = aws_subnet.region2[0].id
  route_table_id = aws_route_table.region2[0].id
}

resource "aws_security_group" "region2" {
  count    = local.on ? 1 : 0
  provider = aws.region2
  name     = "net-lab-region2"
  vpc_id   = aws_vpc.region2[0].id

  ingress {
    description = "ICMP from home region net-lab VPCs"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-region2" }
}
