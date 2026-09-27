# Test — CI/CD, AWS-native (CodeBuild → ECR → ArgoCD)

No layer in this repo builds images or runs pipelines yet — this test adds the
**CI** half by hand (CodeBuild) and reuses the **CD** half that already exists
(ArgoCD, `layer2-platform/00-argocd`). GitOps stays the deploy mechanism in both
this test and `04-TEST-CICD-GITLAB.md`; only the CI engine differs — that split is
itself the thing worth observing.

## 0. Prereqs
- Shared ECR `app` repo already exists (`foundation/02-ecr`, `repo_names`).
- `layer2-platform/00-argocd` applied.
- A git repo CodeBuild can read (GitHub works without extra setup; CodeCommit is
  closed to new customers). A small app with a `Dockerfile` — anything, even a
  one-line `FROM traefik/whoami` works for this test.
- A second small git repo (or a folder in one) holding the **k8s manifests** ArgoCD
  watches — kept separate from app source, standard GitOps split.

## 1. IAM role for CodeBuild
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws iam create-role --role-name codebuild-app-build \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name codebuild-app-build \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-role-policy --role-name codebuild-app-build \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

## 2. `buildspec.yml` in the app repo
```yaml
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com
  build:
    commands:
      - docker build -t $ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com/app:$CODEBUILD_RESOLVED_SOURCE_VERSION .
  post_build:
    commands:
      - docker push $ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com/app:$CODEBUILD_RESOLVED_SOURCE_VERSION
      # bump the tag in the manifests repo so ArgoCD picks it up (git clone + sed + commit + push)
```

## 3. Create the CodeBuild project + webhook
```bash
aws codebuild create-project --name app-build \
  --source type=GITHUB,location=https://github.com/<you>/<app-repo>.git \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:5.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true \
  --service-role "arn:aws:iam::$ACCOUNT:role/codebuild-app-build"

aws codebuild create-webhook --project-name app-build \
  --filter-groups '[[{"type":"EVENT","pattern":"PUSH"}]]'
```
`privilegedMode=true` is required — CodeBuild runs Docker-in-Docker to build images.

## 4. ArgoCD Application watching the manifests repo
```bash
kubectl apply -n argocd -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/<manifests-repo>.git
    targetRevision: main
    path: .
  destination: { server: https://kubernetes.default.svc, namespace: default }
  syncPolicy: { automated: { prune: true, selfHeal: true } }
EOF
```

## 5. Run it end to end
```bash
git -C <app-repo> commit --allow-empty -m "trigger build" && git -C <app-repo> push
aws codebuild list-builds-for-project --project-name app-build
kubectl -n argocd get application app -w   # Synced once the manifest bump lands
kubectl rollout status deploy/app
```

## 6. Cleanup
```bash
aws codebuild delete-project --name app-build
aws iam detach-role-policy --role-name codebuild-app-build --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam detach-role-policy --role-name codebuild-app-build --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
aws iam delete-role --role-name codebuild-app-build
kubectl delete application app -n argocd
```
