# 00-tf-backend

Creates the remote-state backend the other layers use: an S3 bucket (versioned,
encrypted, private) + a DynamoDB lock table. Keeps its own state local.

Apply first, then point each layer's `backend "s3"` block at the outputs and run
`tofu init -migrate-state`. See `3-outputs.tf` for the backend snippet.

No enable toggle — foundational and ~pennies/mo.
