# Deliberately fails every time — the lab's point is the compensation path, not a working
# payment integration. Flip this to succeed and the saga completes normally instead.
def handler(event, context):
    print("charge_payment: declining on purpose", event)
    raise Exception("payment_declined")
