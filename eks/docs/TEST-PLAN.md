# Test plan (post-cluster)

Once a cluster is up (any env), run these as separate exercises — each is its own
lab/spike, not part of the base layer build.

- [ ] **Network — ingress/Gateway API, REST vs gRPC.** Compare classic Ingress
  (ALB Controller / Istio ingress) against Gateway API; test both a RESTful
  service and a gRPC service through each, including the L4-vs-L7 gRPC
  load-balancing gotcha already documented in `../ad-hoc/grpc-conn-debug/`.
- [ ] **Observability — AWS-native.** AMP + AMG (`06-observability-aws`),
  Prometheus `remoteWrite` into AMP, dashboards in AMG.
- [ ] **Observability — Grafana stack (self-hosted).** kube-prometheus-stack
  (layer2/01) with durable storage (gp3 PVC), Grafana + Loki/Tempo if in scope.
- [ ] **CI/CD — AWS-native.** e.g. CodePipeline/CodeBuild (or ArgoCD sourcing
  from CodeCommit-equivalent) deploying into the cluster.
- [ ] **CI/CD — GitLab.** GitLab CI runner on the cluster (or GitLab-managed
  runner) + ArgoCD GitOps pull, deploying into the cluster.

Add more rows here as new test ideas come up — this list is expected to grow.
