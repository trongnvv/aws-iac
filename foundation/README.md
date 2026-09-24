# foundation

Account-level, long-lived, shared across every stack (eks and beyond). Set up
**once**, rarely touched. Do NOT tear this down with a cluster.

| # | Folder | What | State |
|---|---|---|---|
| 00 | tf-backend | S3 state bucket (native S3 locking, `use_lockfile`) — creates the backend | local |
| 01 | dns | Route 53 hosted zone + regional wildcard ACM cert | S3 |

## Apply (once)
```bash
./apply.sh
# or manually:
#   cd 00-tf-backend && tofu init && tofu apply     # local state, makes the S3 backend
#   cd 01-dns        && tofu init && tofu apply     # uses the S3 backend
```

- After `01-dns`: copy the `name_servers` output into the registrar (delegation).
- **Zone already exists** (e.g. Phase-1 lab)? Import instead of duplicating:
  `cd 01-dns && tofu import aws_route53_zone.main <ZONE_ID>`.

Consumed by `eks/`: the domain (external-dns) + `regional_cert_arn` (ALB TLS).
