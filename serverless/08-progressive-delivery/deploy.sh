#!/usr/bin/env bash
# Single layer. Terraform only sets up the static infra (function, alias, CodeDeploy app/group,
# alarm) — triggering an actual canary rollout is an imperative action, done here with the AWS
# CLI, same as a real CI/CD pipeline's deploy step would.
set -euo pipefail
cd "$(dirname "$0")"

(cd 1-pipeline && tofu init -input=false >/dev/null && tofu apply -auto-approve)

FN=$(cd 1-pipeline && tofu output -raw function_name)
ALIAS=$(cd 1-pipeline && tofu output -raw alias_name)
APP=$(cd 1-pipeline && tofu output -raw codedeploy_app_name)
DG=$(cd 1-pipeline && tofu output -raw codedeploy_deployment_group)
CURRENT=$(cd 1-pipeline && tofu output -raw current_version)

echo "=== publishing v2 (good) and canary-rolling the 'live' alias onto it ==="
(cd 1-pipeline && tofu apply -auto-approve -var version_label=v2 -var fail=false | tail -5)
NEW=$(cd 1-pipeline && tofu output -raw current_version)

if [ "$NEW" = "$CURRENT" ]; then
  echo "no new version published (code unchanged) — nothing to canary-roll this run"
  exit 0
fi

# Build the create-deployment request with Python (not shell string-building) — the appspec has
# to be embedded as a JSON-encoded STRING inside the outer request, which is exactly the kind of
# nested escaping shell quoting gets wrong.
python3 -c "
import json
appspec = {
    'version': 0.0,
    'Resources': [{'hello': {'Type': 'AWS::Lambda::Function', 'Properties': {
        'Name': '$FN', 'Alias': '$ALIAS', 'CurrentVersion': '$CURRENT', 'TargetVersion': '$NEW',
    }}}],
}
request = {
    'applicationName': '$APP',
    'deploymentGroupName': '$DG',
    'revision': {'revisionType': 'AppSpecContent', 'appSpecContent': {'content': json.dumps(appspec)}},
}
json.dump(request, open('/tmp/net-lab-pd-deploy-request.json', 'w'))
"

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --cli-input-json file:///tmp/net-lab-pd-deploy-request.json \
  --profile default --region ap-southeast-1 --query deploymentId --output text)

echo "Canary deployment $DEPLOYMENT_ID started — 10% traffic for 5 min, then 100%."
echo "Watch it: aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --profile default --region ap-southeast-1 --query 'deploymentInfo.status'"
echo
echo "Rollback demo: re-run with FAIL=true baked into a new version —"
echo "  (cd 1-pipeline && tofu apply -auto-approve -var version_label=v3 -var fail=true)"
echo "then trigger a deployment the same way; invoking the alias during the canary window trips"
echo "the Errors alarm and CodeDeploy rolls the alias back automatically."
