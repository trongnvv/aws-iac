# 05-external-secrets

External Secrets Operator — pulls secrets from AWS Secrets Manager / SSM into
Kubernetes Secrets. Uses the IAM role from `layer0/04-addon-iam`.

**Installs:** `helmfile.yaml` (external-secrets chart) + a `SecretStore`.
