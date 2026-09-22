# 03-external-dns

ExternalDNS — syncs Ingress/Service hostnames to Route 53.
Uses the IAM role from `layer0/04-addon-iam`.

**Installs:** `helmfile.yaml` (external-dns chart), scoped to a hosted zone.
