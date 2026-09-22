# Aggregates findings from GuardDuty/Config/Inspector and scores against
# standards (CIS, AWS Foundational Security Best Practices).
resource "aws_securityhub_account" "this" {
  count = var.enable_securityhub ? 1 : 0
}
