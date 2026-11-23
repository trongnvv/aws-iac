import json


def handler(event, context):
    print("consumer_b received:", json.dumps(event))
    return {"received": True}
