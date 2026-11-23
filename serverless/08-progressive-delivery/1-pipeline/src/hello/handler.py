import os


def handler(event, context):
    # FAIL=true is the rollback demo: deploy.sh can publish this as a bad version to prove the
    # CloudWatch alarm trips CodeDeploy's auto-rollback mid-canary.
    if os.environ.get("FAIL") == "true":
        raise Exception("deliberate failure — rollback demo")
    return {"message": "hello", "version": os.environ.get("VERSION_LABEL", "v1")}
