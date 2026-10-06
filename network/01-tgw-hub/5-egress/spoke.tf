# ── Spoke private subnets — no IGW; internet only via the central NAT (proves egress) ─────────
resource "aws_subnet" "private" {
  for_each          = local.spokes
  vpc_id            = local.vo.vpc_ids[each.key]
  cidr_block        = cidrsubnet(local.vo.vpc_cidrs[each.key], 8, 100) # 10.x.100.0/24
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "net-lab-${each.key}-private" }
}

resource "aws_route_table" "private" {
  for_each = local.spokes
  vpc_id   = local.vo.vpc_ids[each.key]
  tags     = { Name = "net-lab-${each.key}-private" }
}

resource "aws_route" "private_default" {
  for_each               = local.spokes
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.tgw_id
}

resource "aws_route_table_association" "private" {
  for_each       = local.spokes
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Private test host — no public IP; its SSM agent + any curl reaches the internet via the shared NAT.
resource "aws_instance" "private" {
  for_each               = local.spokes
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = aws_subnet.private[each.key].id
  vpc_security_group_ids = [local.vo.sg_ids[each.key]]
  iam_instance_profile   = data.terraform_remote_state.ssm.outputs.instance_profile_name
  tags                   = { Name = "net-lab-${each.key}-private" }
}
