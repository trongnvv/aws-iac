def handler(event, context):
    for record in event["Records"]:
        if record["eventName"] != "INSERT":
            continue
        new_image = record["dynamodb"].get("NewImage", {})
        sk = new_image.get("SK", {}).get("S", "")
        if sk.startswith("ORDER#"):
            pk = new_image.get("PK", {}).get("S", "")
            print(f"new order inserted: {sk} for customer {pk}")
    return {"processed": len(event["Records"])}
