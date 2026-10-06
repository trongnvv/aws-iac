# SG on the interface endpoint ENI. The ENI is what the consumer actually talks to, so this SG gates
# consumer → service. Allow 80 (our HTTP service) and 443 (common for real PrivateLink services) from
# within VPC B.
resource "aws_security_group" "endpoint" {
  name   = "net-lab-pl-endpoint"
  vpc_id = local.vpc_b_id

  ingress {
    description = "HTTP from VPC B"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [local.vpc_b_cidr]
  }
  ingress {
    description = "HTTPS from VPC B"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [local.vpc_b_cidr]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-pl-endpoint" }
}

# Interface endpoint in VPC B pointing at the provider's endpoint service. This drops an ENI into B's
# subnet with a private IP from B's CIDR — the consumer hits THAT IP, and AWS PrivateLink tunnels it to
# the NLB in VPC A. No route between the two 10.0.0.0/16 blocks is ever consulted → overlap is irrelevant.
# private_dns_enabled=false: custom endpoint services have no verified private DNS by default, so we use
# the endpoint's own generated DNS name (see outputs). Flipping this on is the stretch goal.
resource "aws_vpc_endpoint" "service" {
  vpc_id              = local.vpc_b_id
  service_name        = local.endpoint_service_nm
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [local.subnet_b]
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false
  tags                = { Name = "net-lab-pl-endpoint" }
}
