import time

# Stand-in for a heavy import/init cost (e.g. loading a large model or SDK client) — kept
# dependency-free on purpose. A function with PROVISIONED CONCURRENCY pays this cost ahead of
# time (off the caller's clock); an on-demand $LATEST invoke pays it inline as "Init Duration".
time.sleep(1)


def handler(event, context):
    return {"ok": True}
