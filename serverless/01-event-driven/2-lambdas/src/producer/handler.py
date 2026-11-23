import boto3
import json
import os
import uuid

client = boto3.client("events")


def handler(event, context):
    detail = {"order_id": str(uuid.uuid4()), "amount": 42}
    response = client.put_events(
        Entries=[
            {
                "Source": "net-lab.orders",
                "DetailType": "order.created",
                "Detail": json.dumps(detail),
                "EventBusName": os.environ["EVENT_BUS_NAME"],
            }
        ]
    )
    return {"put_events_response": response}
