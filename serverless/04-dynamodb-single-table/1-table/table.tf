# One table, two entity types — access patterns, not a table per entity:
#   get a customer + ALL their orders  → Query PK = CUSTOMER#<id>              (base table)
#   look up ONE order by its own id    → Query GSI1PK = ORDER#<order_id>       (GSI1)
# Customer item:  PK=CUSTOMER#<id>              SK=CUSTOMER#<id>       GSI1PK=CUSTOMER#<id>   GSI1SK=METADATA
# Order item:     PK=CUSTOMER#<id>              SK=ORDER#<order_id>   GSI1PK=ORDER#<order_id> GSI1SK=ORDER#<order_id>
resource "aws_dynamodb_table" "this" {
  name         = "net-lab-single-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}
