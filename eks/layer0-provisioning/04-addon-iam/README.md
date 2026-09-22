# 04-addon-iam

IRSA / Pod Identity roles consumed by the layer1 Helm add-ons. Kept in one place
so add-on IAM is auditable and the Helm charts only reference role ARNs.

**Builds roles for:**
- AWS Load Balancer Controller
- ExternalDNS (Route 53)
- External Secrets Operator (Secrets Manager / SSM)
- cert-manager (DNS-01 via Route 53), if used

**Outputs:** one `*_role_arn` per add-on → exported to `env.sh` for Helmfile.
