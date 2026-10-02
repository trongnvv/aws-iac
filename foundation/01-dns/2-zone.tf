# Set the 4 output NS records at the registrar; ACM validation fails until delegation resolves.
# Zone already exists? Import, don't duplicate: tofu import aws_route53_zone.main <ZONE_ID>
resource "aws_route53_zone" "main" {
  name = var.domain
}
