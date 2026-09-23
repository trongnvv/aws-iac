# Centralized egress inspection with a domain allowlist. All gated by
# enable_network_firewall. Path when on: app subnet → firewall endpoint (its own
# subnet) → NAT → IGW. NAT is stateful so return traffic doesn't need the firewall
# for SNI/HTTP-host allowlisting (the decision is made on the outbound request).

# Dedicated firewall subnets (one per AZ) — the endpoint must not share the app subnet.
resource "aws_subnet" "firewall" {
  count             = var.enable_network_firewall ? length(var.azs) : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "firewall-${var.azs[count.index]}" }
}

resource "aws_networkfirewall_rule_group" "domain_allow" {
  count    = var.enable_network_firewall ? 1 : 0
  capacity = 100
  name     = "${var.cluster_name}-egress-allowlist"
  type     = "STATEFUL"
  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = var.allowed_domains
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  count = var.enable_network_firewall ? 1 : 0
  name  = "${var.cluster_name}-egress-policy"
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.domain_allow[0].arn
    }
  }
}

resource "aws_networkfirewall_firewall" "this" {
  count               = var.enable_network_firewall ? 1 : 0
  name                = "${var.cluster_name}-egress-fw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this[0].arn
  vpc_id              = aws_vpc.main.id
  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }
}

# Per-AZ firewall endpoint id, keyed by AZ, for the app default route.
locals {
  fw_endpoints = var.enable_network_firewall ? {
    for ss in aws_networkfirewall_firewall.this[0].firewall_status[0].sync_states :
    ss.availability_zone => one(ss.attachment).endpoint_id
  } : {}
}

# App egress → firewall endpoint (replaces the NAT default route when on).
resource "aws_route" "app_firewall" {
  count                  = var.enable_network_firewall ? length(var.azs) : 0
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.fw_endpoints[var.azs[count.index]]
}

# Firewall subnet → NAT (traffic continues out after inspection).
resource "aws_route_table" "firewall" {
  count  = var.enable_network_firewall ? length(var.azs) : 0
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[var.nat_per_az ? count.index : 0].id
  }
  tags = { Name = "firewall-rt-${var.azs[count.index]}" }
}

resource "aws_route_table_association" "firewall" {
  count          = var.enable_network_firewall ? length(var.azs) : 0
  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}

output "firewall_arn" {
  value = var.enable_network_firewall ? aws_networkfirewall_firewall.this[0].arn : null
}
