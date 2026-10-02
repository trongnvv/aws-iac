# Hands-on — deploy grpc-conn-debug (plan 2: CodePipeline → ECR → ArgoCD)

End-to-end deployment of the grpc-conn-debug app: AWS-native CI (CodePipeline + CodeBuild)
builds + pushes images to ECR; CD is ArgoCD + Image Updater pulling the shared `helm/app`
OCI chart. Markers: 🖐️ manual · ⚙️ tofu/helmfile · ⚠️ attention.

Design & "why" live in `foundation/04-app-cicd/README.md` and `gitops/argo-simple/README.md`.
This is the runbook.

## Prereq
- ⚙️ `foundation`: `00-tf-backend` + `01-dns` applied; 🖐️ NS records set at the registrar.
  (`02-ecr` not required — chart and images self-provision their ECR repos.)
- **`03-cicd` done + chart published**: `helm/app:0.7.0` exists in ECR (ArgoCD pulls it).
- Dev cluster `eks-dev` up (`eks/envs/dev` 00-infra + 01-addons applied).

## 1. Push the repos 🖐️
- `applications/grpc-conn-debug` — app code + `buildspec.yml` → `main`.
- `gitops/argo-simple` — `apps/grpc-conn-debug/*` → `main`.

## 2. Enable Pod Identity agent 🖐️ ⚠️
The `eks-pod-identity-agent` addon must be on `eks-dev` — without it, ArgoCD/Image Updater
get no ECR access.

## 3. Apply the CI pipeline (foundation/04-app-cicd) ⚙️
```bash
cd aws-iac/foundation/04-app-cicd && tofu init && tofu apply
```
Creates: CodePipeline `grpc-conn-debug`, CodeBuild (DinD), S3 artifact. Reuses the `03-cicd`
GitLab connection. ⚠️ **03 must be applied before 04** (remote-state dependency). **No cluster
resources here** — the Image Updater + ESO ECR Pod Identity roles live in eks
`00-infra/03-addon-iam` (applied with the cluster, step 0 prereq).

## 4. Deploy ArgoCD + Image Updater (eks platform) ⚙️
```bash
cd aws-iac/eks/envs/dev && ./deploy.sh 02-platform
```
Installs Argo CD (domain `argocd.trongnv.space`, hardcoded admin pass) + an External
Secrets-managed `repo-ecr-helm` secret (fresh ECR token, auto-refreshed) and
`argocd-image-updater` (ECR auth via Pod Identity).

## 5. Add the GitLab token to ArgoCD 🖐️
Create a **Project Access Token** on `argo-simple` (role Maintainer, scope `write_repository`),
then (don't commit the token):
```bash
kubectl apply -n argocd -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: repo-argo-simple
  namespace: argocd
  labels: { argocd.argoproj.io/secret-type: repository }
stringData:
  type: git
  url: https://gitlab.com/trongnvv-platform/gitops/argo-simple.git
  username: oauth2          # Deploy Token: use the deploy token's username instead
  password: <PASTE_TOKEN>
EOF
```
One token serves both: ArgoCD reads the values source + Image Updater commits tag bumps.
⚠️ The token has an expiry — set it far out, or swap for an SSH deploy key (no expiry) later.

## 5b. ECR OCI chart repo — managed by External Secrets ⚙️
The `repo-ecr-helm` secret (OCI, `enableOCI` + username/password) is **minted and auto-refreshed
by External Secrets Operator** (`ecr-repo-externalsecret.yaml`, applied with `02-platform`). ESO
uses the external-secrets controller's Pod Identity to fetch a fresh ECR token (refresh 10h).
Nothing to apply by hand.

## 6. Apply the Applications 🖐️
The shared gateway-infra (GatewayClass + LoadBalancerConfiguration for the `-02` gateways) stays
in IaC — deploy it first: ⚙️ `aws-iac/eks` `./deploy.sh 03-application`. Then the apps:
```bash
kubectl apply -f apps/grpc-conn-debug/server.yaml   # from argo-simple
kubectl apply -f apps/grpc-conn-debug/client.yaml
kubectl apply -f apps/grpc-conn-debug/image-updater.yaml   # ImageUpdater CRs (v1.x, not annotations)
```

## 7. Trigger CI + verify 🖐️
```bash
# push a commit, or run manually:
aws codebuild start-build --project-name grpc-conn-debug-build --region ap-southeast-1
aws ecr describe-images --repository-name grpc-conn-debug/server --region ap-southeast-1 \
  --query 'imageDetails[].imageTags'
```

## 8. Verify CD
Values start at `:d-0000000` (no such image). Once a real `d-<sha>` is in ECR, Image Updater
detects it, commits the tag to `argo-simple`, and ArgoCD syncs.
```bash
kubectl -n argocd get applications grpc-server grpc-client
kubectl -n grpc-debug get pods
```
- UI: `https://argocd.trongnv.space` (admin / the hardcoded lab pass). CLI: `argocd login
  argocd.trongnv.space --grpc-web`.

## ⚠️ Verify live (built blind, may need tuning)
- **ESO ECRAuthorizationToken generator** → `repo-ecr-helm` — that the generator uses the
  external-secrets controller Pod Identity and the ExternalSecret template populates the repo
  secret correctly (and the ESO `generators.external-secrets.io` CRD is present).
- **Image Updater** chart `1.3.1` (v1.x) — verify the **ImageUpdater CR** schema
  (`applicationRefs` / `images` / `manifestTargets.helm.spec`) + git write-back on a multi-source app.
- ECR repos are **IMMUTABLE** — re-running the same commit pushes no new tag (not an error).
