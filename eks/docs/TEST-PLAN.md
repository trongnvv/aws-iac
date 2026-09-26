# Test plan (post-cluster)

Once a cluster is up (any env), run these as separate exercises — each is its own
lab/spike, not part of the base layer build.

- [ ] **Network — ingress/Gateway API, REST vs gRPC.** Compare classic Ingress
  (ALB Controller / Istio ingress) against Gateway API; test both a RESTful
  service and a gRPC service through each, including the L4-vs-L7 gRPC
  load-balancing gotcha already documented in `../ad-hoc/grpc-conn-debug/`.
  → `hands-on/TEST-INGRESS-GATEWAY-API.md`
- [ ] **Observability — AWS-native.** AMP (`05-observability-aws`), an ADOT
  collector `remoteWrite`-ing into it, dashboards in AMG.
  → `hands-on/TEST-OBSERVABILITY-AWS-NATIVE.md`
- [ ] **Observability — Grafana stack (self-hosted).** kube-prometheus-stack
  (layer2/01) with durable storage (gp3 PVC), Grafana + Loki/Tempo if in scope.
  → `hands-on/TEST-OBSERVABILITY-GRAFANA-STACK.md`
- [ ] **CI/CD — AWS-native.** CodeBuild building + pushing to the shared ECR,
  ArgoCD GitOps pull deploying into the cluster.
  → `hands-on/TEST-CICD-AWS-NATIVE.md`
- [ ] **CI/CD — GitLab.** GitLab CI runner on the cluster pushing to the shared
  ECR, same ArgoCD GitOps pull deploying into the cluster.
  → `hands-on/TEST-CICD-GITLAB.md`

Add more rows here as new test ideas come up — this list is expected to grow.
