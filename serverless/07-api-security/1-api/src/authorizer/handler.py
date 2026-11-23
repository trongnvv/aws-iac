import json

# Stand-in for real JWT/Cognito validation — the lab's point is the authorizer wiring (custom
# auth, 403 on reject), not a crypto library. Swap this check for a real JWT verify in production.
EXPECTED_TOKEN = "net-lab-secret-token"


def handler(event, context):
    token = event.get("authorizationToken", "")
    effect = "Allow" if token == f"Bearer {EXPECTED_TOKEN}" else "Deny"
    return {
        "principalId": "net-lab-user",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{
                "Action": "execute-api:Invoke",
                "Effect": effect,
                "Resource": event["methodArn"],
            }],
        },
    }
