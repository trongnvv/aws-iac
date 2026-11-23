def handler(event, context):
    print("reserve_inventory: OK, reserving", event)
    return {**event, "inventory_reserved": True}
