# 00-tf-backend

Creates the remote-state backends the other layers use: **two** S3 buckets (versioned, encrypted,
private, native S3 locking) — `eks-iac-tfstate` (eks + foundation) and `network-iac-tfstate` (the
`network/*` labs). Keeps its own state local.

Apply first, then point each layer's `backend "s3"` block at the outputs and run
`tofu init -migrate-state`. See `3-outputs.tf` for the backend snippet.

No enable toggle — foundational and ~pennies/mo.

## Adopting the existing bucket (no recreate)
`var.adopt_buckets` config-driven-**imports** pre-existing buckets from the real AWS resource (by name)
on `apply` — so an already-created `eks-iac-tfstate` is adopted, not recreated, while new buckets
(`network-iac-tfstate`) are just created. No manual `state mv`.
- **Fresh account** (eks bucket not created yet) → set `adopt_buckets = []` so apply creates both.
- If OpenTofu still reports the bucket managed under the old `aws_s3_bucket.state` address (from an
  earlier apply of the single-resource version), `tofu state rm aws_s3_bucket.state` (and its
  `_versioning`/`_server_side_encryption_configuration`/`_public_access_block`) **once**, then apply —
  the import adopts the real bucket cleanly.
