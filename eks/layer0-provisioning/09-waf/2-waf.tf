# Regional web ACL for the ALB. Attach via the Ingress annotation
# alb.ingress.kubernetes.io/wafv2-acl-arn = <web_acl_arn> (LBC does the association).
resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0
  name  = var.web_acl_name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.web_acl_name
    sampled_requests_enabled   = true
  }
}

output "web_acl_arn" {
  value = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}
