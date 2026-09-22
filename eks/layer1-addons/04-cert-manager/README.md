# 04-cert-manager

cert-manager — issues TLS certs (ACME DNS-01 via Route 53).
Alternative: terminate TLS at the ALB with ACM instead.

**Installs:** `helmfile.yaml` (cert-manager chart) + `ClusterIssuer`.
