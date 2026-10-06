# 00-tf-backend

Creates the remote-state backends the other layers use: **two** S3 buckets (versioned, encrypted,
private, native S3 locking) — `eks-iac-tfstate` (eks + foundation) and `network-iac-tfstate` (the
`network/*` labs). Keeps its own state local.

Apply first, then point each layer's `backend "s3"` block at the outputs and run
`tofu init -migrate-state`. See `3-outputs.tf` for the backend snippet.

No enable toggle — foundational and ~pennies/mo.

## If `eks-iac-tfstate` is already in this state (one-time)
The buckets now use `for_each` (`aws_s3_bucket.this["<name>"]`). If an earlier apply created the eks
bucket as the old single `aws_s3_bucket.state`, rename it in state **once** so `apply` doesn't try to
recreate it (then apply only adds `network-iac-tfstate`):
```bash
tofu state mv 'aws_s3_bucket.state'                                      'aws_s3_bucket.this["eks-iac-tfstate"]'
tofu state mv 'aws_s3_bucket_versioning.state'                          'aws_s3_bucket_versioning.this["eks-iac-tfstate"]'
tofu state mv 'aws_s3_bucket_server_side_encryption_configuration.state' 'aws_s3_bucket_server_side_encryption_configuration.this["eks-iac-tfstate"]'
tofu state mv 'aws_s3_bucket_public_access_block.state'                 'aws_s3_bucket_public_access_block.this["eks-iac-tfstate"]'
```
(Fresh account / never applied → skip this; `tofu apply` just creates both buckets.)
