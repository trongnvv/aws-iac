def handler(event, context):
    print("ship_order: shipped", event)
    return {**event, "shipped": True}
