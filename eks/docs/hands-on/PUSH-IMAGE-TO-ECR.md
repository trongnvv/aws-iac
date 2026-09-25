# Push a local image to ECR

Build an image locally and push it to the shared ECR (`foundation/02-ecr`). Needs
Docker/Podman + AWS creds (`hands-on/AWS-CREDENTIALS.md`).

> ⚠️ **Nodes are arm64 (Graviton t4g/m7g).** Build for `linux/arm64` (or multi-arch),
> or pods crash with `exec format error`. See step 3.

## 0. Set variables
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-southeast-1
REPO=app                                   # a repo in foundation/02-ecr repo_names
TAG=v1
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
IMAGE="$REGISTRY/$REPO:$TAG"
```

## 1. Make sure the repo exists
It's created by `foundation/02-ecr` (`repo_names`). To add a new one:
```bash
# edit foundation/02-ecr repo_names to include "app", then:
(cd ../../../foundation/02-ecr && tofu apply)
# quick check:
aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" >/dev/null && echo "repo ok"
```

## 2. Log Docker in to ECR
```bash
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
```

## 3. Build (arm64 to match the nodes)
```bash
# single-arch arm64:
docker build --platform linux/arm64 -t "$IMAGE" .

# OR multi-arch (amd64+arm64) with buildx — builds AND pushes in one step:
docker buildx build --platform linux/amd64,linux/arm64 -t "$IMAGE" --push .
```

## 4. Tag + push (skip if you used `buildx --push`)
```bash
# if you built with a local name instead of $IMAGE:
# docker tag myapp:local "$IMAGE"
docker push "$IMAGE"
```

## 5. Verify
```bash
aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
  --query 'imageDetails[].imageTags' --output text
# scan findings (scan-on-push is enabled):
aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag=$TAG --region "$REGION" \
  --query 'imageScanFindingsSummary' 2>/dev/null || true
```

## 6. Use it in Kubernetes
```yaml
# Deployment / Pod spec
containers:
  - name: app
    image: <account>.dkr.ecr.ap-southeast-1.amazonaws.com/app:v1   # = $IMAGE
```
Nodes pull it automatically via the node role's `AmazonEC2ContainerRegistryReadOnly`
(same-account). No imagePullSecret needed.

## Notes
- **Immutable tags:** the repo is `IMMUTABLE` — you can't overwrite a tag. Push a new
  tag each build (`v2`, a git SHA, etc.). Never reuse `v1`.
- **Promotion:** build once, push once; promote the **same digest** across envs by
  reusing the tag/digest (don't rebuild per env). That's why ECR is shared, not per-env.
- **Cross-account** (dev/prod in different accounts): add an ECR repository policy on
  `foundation/02-ecr` allowing the other account's node role to pull.
- **Private API / no NAT to Docker Hub:** base images from Docker Hub still need egress
  (NAT) at build time on your machine; the cluster pulls from ECR via VPC endpoint.
