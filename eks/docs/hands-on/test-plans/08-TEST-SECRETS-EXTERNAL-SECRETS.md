# Test — Secret management (External Secrets Operator → AWS Secrets Manager)

The source of truth for secrets is **AWS Secrets Manager**; External Secrets Operator (ESO) pulls
them into Kubernetes `Secret`s and keeps them in sync. Auth is **Pod Identity** — no static AWS
keys in the cluster, and no secret value committed to Git.

## What's already deployed
- ESO (`01-addons/05-external-secrets`, chart `2.11.0`) + a **`ClusterSecretStore`
  `aws-secretsmanager`** (provider AWS SecretsManager, region ap-southeast-1) — uses the
  controller's Pod Identity, no `auth` block.
- IAM: `modules/addon-iam/3-eso.tf` role (SA `external-secrets`), `secretsmanager:GetSecretValue`
  + `DescribeSecret` **scoped to `eso_secret_path` = `prod/*`**.
- API version: `external-secrets.io/v1` (chart 2.11 serves v1; v1beta1 is deprecated).

## Flow
```
AWS Secrets Manager  (secret: prod/hello-db)
        ▲ GetSecretValue  (Pod Identity: eks-dev-external-secrets role, SA external-secrets)
   ESO controller  ──reads ClusterSecretStore aws-secretsmanager──►
        └─ reconciles ExternalSecret (in app ns) ──► creates/updates k8s Secret (same ns)
                                                        └─ Pod envFrom / volume mounts it
   refreshInterval → ESO re-pulls; rotate in Secrets Manager → k8s Secret updates automatically
```

## 0. Prereqs
- `eks-pod-identity-agent` addon on the cluster; `01-addons/05-external-secrets` applied.
- A secret **named under `prod/*`** so the scoped IAM policy allows it (or widen `eso_secret_path`).

## 1. Create the source secret in AWS Secrets Manager
```bash
aws secretsmanager create-secret --name prod/hello-db --region ap-southeast-1 \
  --secret-string '{"username":"app","password":"s3cr3t"}'
```

## 2. ExternalSecret in the app namespace
```bash
kubectl apply -n dev -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: hello-db
  namespace: dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secretsmanager
  target:
    name: hello-db            # the k8s Secret ESO creates
  data:
    - secretKey: username     # key in the k8s Secret
      remoteRef:
        key: prod/hello-db    # SM secret name
        property: username    # JSON field
    - secretKey: password
      remoteRef:
        key: prod/hello-db
        property: password
# Or pull the whole JSON as keys: replace `data:` with
#   dataFrom:
#     - extract: { key: prod/hello-db }
EOF
```

## 3. Verify
```bash
kubectl -n dev get externalsecret hello-db          # STATUS SecretSynced=True
kubectl -n dev get secret hello-db -o jsonpath='{.data.password}' | base64 -d; echo
```

## 4. Rotation
```bash
aws secretsmanager put-secret-value --secret-id prod/hello-db --region ap-southeast-1 \
  --secret-string '{"username":"app","password":"rotated"}'
# within refreshInterval the k8s Secret updates; pods pick it up on restart (or use Reloader)
```

## Concepts
| Thing | Role |
|---|---|
| `ClusterSecretStore` | cluster-wide store config (provider + region + auth). `SecretStore` = namespaced variant |
| `ExternalSecret` | per-app: which SM secret → which k8s Secret keys. `data` (field-by-field) or `dataFrom` (whole) |
| Pod Identity | ESO controller's SA → IAM role → `GetSecretValue`. No static keys |
| `refreshInterval` | how often ESO re-pulls (rotation) |
| **Generators** | dynamic creds, not static SM values — e.g. `ECRAuthorizationToken` (used in `02-platform/00-argocd` to mint the ArgoCD OCI repo token) |

## Gotchas
- **IAM scope** `eso_secret_path = prod/*` — secrets outside `prod/` get `AccessDenied`. Name secrets
  `prod/...` or change the variable in `00-infra/03-addon-iam`.
- **API version** must be `external-secrets.io/v1` (not v1beta1) with chart 2.11.
- `SecretSynced=False` → check the ESO controller logs + that the SA `external-secrets` has the
  Pod Identity association (agent addon on).
- The target k8s Secret is **managed by ESO** — editing it by hand gets reverted on refresh.

## Cleanup / cost
```bash
kubectl -n dev delete externalsecret hello-db
aws secretsmanager delete-secret --secret-id prod/hello-db --region ap-southeast-1 --force-delete-without-recovery
```
Secrets Manager: **~$0.40/secret/month** + API calls — delete test secrets.

## Real use in this repo
- **ArgoCD OCI chart pull** — ESO `ECRAuthorizationToken` generator mints `repo-ecr-helm`
  (`02-platform/00-argocd`), refreshed before the 12h ECR token expiry.
- **ArgoCD git repo secret** — `repo-argo-simple` is minted by ESO from Secrets Manager
  `prod/gitlab-argo-simple-token` (a GitLab deploy token, JSON username+password),
  `02-platform/00-argocd/gitlab-repo-externalsecret.yaml`. The same secret is read by CI (CodeBuild)
  to commit image tags — one credential, no committed token, no hand-applied `kubectl` secret.
