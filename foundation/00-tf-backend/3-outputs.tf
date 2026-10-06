# Wire into each layer's backend "s3" block (bucket + use_lockfile + encrypt).
output "state_buckets" {
  value = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "state_bucket" {
  value = aws_s3_bucket.this["eks-iac-tfstate"].id
}

output "network_state_bucket" {
  value = aws_s3_bucket.this["network-iac-tfstate"].id
}
