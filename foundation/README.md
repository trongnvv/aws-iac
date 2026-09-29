# foundation

Account-level, long-lived, shared across every stack (eks and beyond). Set up
**once**, rarely touched. Do NOT tear this down with a cluster.

| # | Folder | What | State |
|---|---|---|---|
| 00 | tf-backend | S3 state bucket (native S3 locking, `use_lockfile`) — creates the backend | local |
| 01 | dns | Route 53 hosted zone + regional wildcard ACM cert | S3 |
| 02 | ecr | shared image registry — build once, promote same digest across envs | S3 |

## Apply (once)
```bash
./apply.sh
# or manually:
#   cd 00-tf-backend && tofu init && tofu apply     # local state, makes the S3 backend
#   cd 01-dns        && tofu init && tofu apply     # uses the S3 backend
```

- After `01-dns`: copy the `name_servers` output into the registrar (delegation).

Consumed by `eks/`: the domain (external-dns) + `regional_cert_arn` (ALB TLS).

## Resource already exists in AWS? Import, don't recreate

Terraform only manages what's in its **state**. If the hosted zone or the wildcard
ACM cert already exist in the account (registered manually or by an earlier lab), a
plain apply either creates a **duplicate** or fails — specifically the ACM cert's
`domain_validation_options` `for_each` throws *"known only after apply"* because the
cert isn't in state yet, so its validation options are unknown at plan time.

Fix = import the existing resources before applying:
```bash
cd 01-dns
# 1. hosted zone
tofu import aws_route53_zone.main <ZONE_ID>            # e.g. /hostedzone/Z0590155INUXOP2DG7YT

# 2. wildcard ACM cert (must match domain_name=<domain> + SAN *.<domain>)
CERT_ARN=$(aws acm list-certificates --region ap-southeast-1 \
  --query "CertificateSummaryList[?DomainName=='<domain>'].CertificateArn | [0]" --output text)
tofu import aws_acm_certificate.regional "$CERT_ARN"

tofu plan     # verify NO "must be replaced" on the cert (else its domains ≠ config)
tofu apply
```
No need to import the validation records or `aws_acm_certificate_validation`: the
records set `allow_overwrite = true` (apply upserts them idempotently) and the
validation resource resolves immediately when the cert is already `ISSUED`.

**Fresh account (nothing exists yet)?** The first apply hits the same ACM chicken-egg
(validation records `for_each` over a not-yet-created cert). Break it with a two-step
apply — this is only safe when the cert does NOT already exist:
```bash
tofu apply -target=aws_acm_certificate.regional   # create the cert first
tofu apply                                          # validation options now known
```
