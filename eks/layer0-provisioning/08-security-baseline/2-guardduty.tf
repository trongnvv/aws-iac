# Threat detection from VPC flow / DNS / EKS audit logs.
resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}

# EKS audit-log monitoring (runtime monitoring can be added later with its own
# agent-management config).
resource "aws_guardduty_detector_feature" "eks_audit" {
  count       = var.enable_guardduty ? 1 : 0
  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}
