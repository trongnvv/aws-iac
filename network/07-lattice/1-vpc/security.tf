# VPC Lattice sends the target's health check + data traffic from its MANAGED PREFIX LIST, NOT from
# the VPC/consumer CIDR. So the service instance SG must allow HTTP:80 from that prefix list — else the
# health check is dropped and the target shows UNHEALTHY (the classic Lattice gotcha).
data "aws_ec2_managed_prefix_list" "lattice" {
  name = "com.amazonaws.${var.region}.vpc-lattice"
}

# Per-VPC instance SG. Egress-all so the SSM agent works and the client can call the Lattice endpoint.
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-lattice-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  # Lattice health check + data path to the target (the fix for UNHEALTHY).
  ingress {
    description     = "HTTP:80 from the VPC Lattice managed prefix list"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.lattice.id]
  }
  # Kept for in-VPC convenience (e.g. curl localhost / same-VPC probing).
  ingress {
    description = "HTTP:80 from within the VPC"
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
