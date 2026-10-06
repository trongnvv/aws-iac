# The 2 inbound-endpoint IPs — on-prem dnsmasq forwards aws.internal to these (templated by layer 3).
output "inbound_ips" {
  description = "Inbound Resolver endpoint IPs (on-prem forwards *.aws.internal here)."
  value       = [for ip in aws_route53_resolver_endpoint.inbound.ip_address : ip.ip]
}

output "outbound_endpoint_id" { value = aws_route53_resolver_endpoint.outbound.id }
output "inbound_endpoint_id" { value = aws_route53_resolver_endpoint.inbound.id }
output "phz_zone_id" { value = aws_route53_zone.aws_internal.zone_id }
output "corp_local_rule_id" { value = aws_route53_resolver_rule.corp_local.id }
