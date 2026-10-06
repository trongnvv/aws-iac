# --- Provider side (VPC A) ---
# The service EC2 must accept HTTP :80 from the NLB. An NLB with a target in the same subnet has the
# health check + traffic appear to come from within the VPC, so allow HTTP from the VPC CIDR. SSM
# needs no inbound rule (agent dials out).
resource "aws_security_group" "provider_svc" {
  name   = "net-lab-pl-provider-svc"
  vpc_id = aws_vpc.this["a"].id

  ingress {
    description = "HTTP from the NLB / provider VPC"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [local.vpcs["a"]]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-pl-provider-svc" }
}

# --- Consumer side (VPC B) ---
# The consumer test host just needs egress (to hit the endpoint ENI). SSM needs no inbound rule.
resource "aws_security_group" "consumer_host" {
  name   = "net-lab-pl-consumer-host"
  vpc_id = aws_vpc.this["b"].id

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-pl-consumer-host" }
}
