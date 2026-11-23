# The compensating action — undoes reserve_inventory. Runs only when a later step fails.
def handler(event, context):
    print("release_inventory: compensating, releasing reservation", event)
    return {**event, "inventory_reserved": False, "compensated": True}
