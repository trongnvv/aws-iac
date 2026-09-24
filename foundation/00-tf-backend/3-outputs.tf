# Wire this bucket into each layer's backend block, then `tofu init`:
#   backend "s3" {
#     bucket       = "<state_bucket>"
#     key          = "<env>/layer0/<layer>/terraform.tfstate"
#     region       = "ap-southeast-1"
#     use_lockfile = true
#     encrypt      = true
#   }
output "state_bucket" {
  value = aws_s3_bucket.state.id
}
