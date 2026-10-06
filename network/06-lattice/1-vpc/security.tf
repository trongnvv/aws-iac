# Per-VPC instance SG. Egress-all so the SSM agent works and the client can call the Lattice endpoint.
# Ingress HTTP:80 from the VPC's own CIDR — the Lattice managed prefix sends traffic to the service
# instance from a link-local source, but for a type=INSTANCE target group the health check + data
# plane arrive via the VPC, so allowing HTTP from the VPC CIDR (and the Lattice prefix) covers it.
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-lattice-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  ingress {
    description = "HTTP from within the VPC (health check + Lattice data path to the target)"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [each.value]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-lattice-${each.key}" }
}
