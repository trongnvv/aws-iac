# Wire these into each layer's backend block, then `tofu init -migrate-state`:
#   backend "s3" {
#     bucket         = "<state_bucket>"
#     key            = "layer0/01-eks/terraform.tfstate"
#     region         = "ap-southeast-1"
#     dynamodb_table = "<lock_table>"
#     encrypt        = true
#   }
output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}
