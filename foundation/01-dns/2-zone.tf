# Hosted zone. Creating it yields 4 AWS name servers — set these as the domain's
# NS records at the registrar (delegation). ACM validation won't work until
# `dig NS <domain> +short` returns them.
#
# If the zone ALREADY exists (e.g. from the Phase-1 lab), import it instead of
# creating a duplicate:  tofu import aws_route53_zone.main <ZONE_ID>
resource "aws_route53_zone" "main" {
  name = var.domain
}
