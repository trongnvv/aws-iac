# Consumed by eks: external-dns (domain) + ALB (regional_cert_arn for TLS).
output "zone_id" {
  value = aws_route53_zone.main.zone_id
}

# Copy these 4 into the registrar right after apply.
output "name_servers" {
  value = aws_route53_zone.main.name_servers
}

output "domain" {
  value = var.domain
}

output "regional_cert_arn" {
  value = aws_acm_certificate_validation.regional.certificate_arn
}
