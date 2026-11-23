import boto3
import json
import os

client = boto3.client("lambda")


def handler(event, context):
    print(json.dumps({
        "level": "INFO",
        "service": "upstream",
        "message": "invoking downstream",
        "request_id": context.aws_request_id,
    }))
    # Active tracing on both functions + a boto3 call in between is enough for Lambda's runtime
    # to stitch one X-Ray trace across both — no X-Ray SDK import needed for this.
    response = client.invoke(
        FunctionName=os.environ["DOWNSTREAM_FUNCTION_NAME"],
        InvocationType="RequestResponse",
        Payload=json.dumps(event).encode(),
    )
    return json.loads(response["Payload"].read())
