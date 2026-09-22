# Centralized egress inspection with a domain allowlist. NOTE: after apply you
# must route app egress THROUGH the firewall endpoints (app RT → firewall endpoint
# → NAT) — that routing change is environment-specific and documented in README.
resource "aws_networkfirewall_rule_group" "domain_allow" {
  count    = var.enable_network_firewall ? 1 : 0
  capacity = 100
  name     = "egress-domain-allowlist"
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
  name  = "egress-policy"
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
  name                = "egress-fw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this[0].arn
  vpc_id              = local.vpc_id
  dynamic "subnet_mapping" {
    for_each = toset(local.app_subnet_ids)
    content {
      subnet_id = subnet_mapping.value
    }
  }
}

output "firewall_arn" {
  value = var.enable_network_firewall ? aws_networkfirewall_firewall.this[0].arn : null
}
