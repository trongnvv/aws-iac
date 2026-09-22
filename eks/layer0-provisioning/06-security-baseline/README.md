# 08-security-baseline

Account-level security services: GuardDuty (EKS audit-log threat detection),
CloudTrail (API audit → S3), AWS Config (resource compliance → S3), Security Hub
(aggregated findings + CIS/FSBP scoring).

Each service has its own `enable_*` variable, **all default `false`** (they bill
with usage). Enable per-env in `terraform.tfvars`; a regulated/prod env turns
them on. Applying with everything off creates nothing.
