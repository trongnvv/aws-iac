import boto3
import json
import os

table = boto3.resource("dynamodb").Table(os.environ["IDEMPOTENCY_TABLE"])


def handler(event, context):
    # ReportBatchItemFailures: only the failed messages go back to the queue (and eventually the
    # DLQ after maxReceiveCount) — a bad message in a batch of 10 doesn't force-retry the other 9.
    batch_item_failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        body = json.loads(record["body"])

        # Idempotency: SQS is at-least-once — a message CAN be redelivered even after it succeeded.
        # Skipping anything already recorded makes a replay safe instead of double-processing.
        if table.get_item(Key={"message_id": message_id}).get("Item"):
            print(f"skip {message_id}: already processed")
            continue

        if body.get("poison"):
            print(f"fail {message_id}: poison message — retried, then DLQ after 3 attempts")
            batch_item_failures.append({"itemIdentifier": message_id})
            continue

        table.put_item(Item={"message_id": message_id, "body": body})
        print(f"processed {message_id}")

    return {"batchItemFailures": batch_item_failures}
