# 10-backup-aws

S3 bucket for Velero backups + the Pod Identity role Velero (layer2 chart)
assumes to write backups and snapshot EBS volumes.

Gated by `enable_backup` (**default `false`** — backup storage + snapshots cost).
The Velero namespace/service-account are variables that must match the Helm release.
