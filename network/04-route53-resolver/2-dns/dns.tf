# ── AWS side name space: Route 53 private hosted zone `aws.internal` ──────────
# Resolves only inside the AWS VPC (and, via the inbound endpoint, for queries forwarded from on-prem).
resource "aws_route53_zone" "aws_internal" {
  name = "aws.internal"
  vpc {
    vpc_id = local.aws_vpc_id
  }
  tags = { Name = "net-lab-r53-aws-internal" }
}

# Sample record the on-prem side will dig: test.aws.internal → a dummy A.
resource "aws_route53_record" "test" {
  zone_id = aws_route53_zone.aws_internal.zone_id
  name    = "test.aws.internal"
  type    = "A"
  ttl     = 60
  records = ["10.20.99.99"] # dummy target — the lab proves resolution, not reachability of this IP
}

# ── Resolver SGs ─────────────────────────────────────────────────────────────
# Inbound endpoint: accepts DNS from the on-prem CIDR (on-prem dnsmasq forwards aws.internal here).
resource "aws_security_group" "inbound" {
  name   = "net-lab-r53-inbound"
  vpc_id = local.aws_vpc_id

  ingress {
    description = "DNS UDP from on-prem"
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.onprem_cidr]
  }
  ingress {
    description = "DNS TCP from on-prem"
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.onprem_cidr]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-r53-inbound" }
}

# Outbound endpoint: sends DNS toward on-prem. Egress to the on-prem CIDR on 53 is what matters.
resource "aws_security_group" "outbound" {
  name   = "net-lab-r53-outbound"
  vpc_id = local.aws_vpc_id

  egress {
    description = "DNS UDP to on-prem"
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.onprem_cidr]
  }
  egress {
    description = "DNS TCP to on-prem"
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.onprem_cidr]
  }
  tags = { Name = "net-lab-r53-outbound" }
}

# ── INBOUND endpoint (on-prem → AWS) ─────────────────────────────────────────
# Gives on-prem a fixed set of IPs to forward aws.internal queries to; AWS resolves them against the PHZ.
resource "aws_route53_resolver_endpoint" "inbound" {
  name      = "net-lab-r53-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.inbound.id]

  ip_address {
    subnet_id = local.aws_subnet_ids["a"]
  }
  ip_address {
    subnet_id = local.aws_subnet_ids["b"]
  }
  tags = { Name = "net-lab-r53-inbound" }
}

# ── OUTBOUND endpoint (AWS → on-prem) ────────────────────────────────────────
# The egress path for queries matched by the forwarding rule below.
resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "net-lab-r53-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.outbound.id]

  ip_address {
    subnet_id = local.aws_subnet_ids["a"]
  }
  ip_address {
    subnet_id = local.aws_subnet_ids["b"]
  }
  tags = { Name = "net-lab-r53-outbound" }
}

# Forwarding rule: anything under corp.local → forward via the outbound endpoint to the on-prem DNS IP.
resource "aws_route53_resolver_rule" "corp_local" {
  name                 = "net-lab-r53-corp-local"
  domain_name          = "corp.local"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip   = var.onprem_dns_ip # static on-prem dnsmasq IP (see variables.tf)
    port = 53
  }
  tags = { Name = "net-lab-r53-corp-local" }
}

# Associate the rule with the AWS VPC → queries from AWS hosts for *.corp.local use it.
resource "aws_route53_resolver_rule_association" "corp_local" {
  resolver_rule_id = aws_route53_resolver_rule.corp_local.id
  vpc_id           = local.aws_vpc_id
}
