# Wire into each layer's backend "s3" block (bucket + use_lockfile + encrypt).
output "state_bucket" {
  value = aws_s3_bucket.state.id
}
