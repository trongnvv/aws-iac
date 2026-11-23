import json


def handler(event, context):
    print("consumer_a received:", json.dumps(event))
    return {"received": True}
