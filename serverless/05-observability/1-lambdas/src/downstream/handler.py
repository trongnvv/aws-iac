import json
import time


def handler(event, context):
    start = time.time()
    # ... stand-in for real work ...
    duration_ms = (time.time() - start) * 1000

    # Structured log — one JSON object per line, filterable in CloudWatch Logs Insights by field.
    print(json.dumps({
        "level": "INFO",
        "service": "downstream",
        "message": "processed",
        "request_id": context.aws_request_id,
    }))

    # CloudWatch Embedded Metric Format — this JSON line is auto-extracted into a real metric
    # (namespace net-lab/Serverless, name ProcessingTimeMs), no separate PutMetricData call/cost.
    print(json.dumps({
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": "net-lab/Serverless",
                "Dimensions": [["service"]],
                "Metrics": [{"Name": "ProcessingTimeMs", "Unit": "Milliseconds"}],
            }],
        },
        "service": "downstream",
        "ProcessingTimeMs": duration_ms,
    }))

    return {"ok": True}
