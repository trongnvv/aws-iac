# Test plan (post-cluster)

Once a cluster is up (any env), run these as separate exercises — each is its own
lab/spike, not part of the base layer build. Full write-up per item lives in
`hands-on/test-plans/`.

1. [ ] **Ingress vs Gateway API, REST vs gRPC.** Compare classic Ingress (ALB
   Controller) against Gateway API (LBC ALB, GatewayClass `alb`); test both a
   RESTful service and a gRPC service through each, including the L4-vs-L7 gRPC
   load-balancing gotcha already documented in `../envs/dev/03-application/00-grpc-debug/`.
   → `hands-on/test-plans/01-TEST-INGRESS-GATEWAY-API.md`
2. [ ] **CI/CD — AWS-native.** CodeBuild building + pushing to the shared ECR,
   ArgoCD GitOps pull deploying into the cluster.
   → `hands-on/test-plans/02-TEST-CICD-AWS-NATIVE.md`
3. [ ] **Observability — AWS-native.** AMP (`05-observability-aws`), an ADOT
   collector `remoteWrite`-ing into it, dashboards in AMG.
   → `hands-on/test-plans/03-TEST-OBSERVABILITY-AWS-NATIVE.md`
4. [ ] **CI/CD — GitLab.** GitLab CI runner on the cluster pushing to the shared
   ECR, same ArgoCD GitOps pull deploying into the cluster.
   → `hands-on/test-plans/04-TEST-CICD-GITLAB.md`
5. [ ] **Observability — Grafana stack (self-hosted).** kube-prometheus-stack
   (layer2/01) with durable storage (gp3 PVC), Grafana + Loki/Tempo if in scope.
   → `hands-on/test-plans/05-TEST-OBSERVABILITY-GRAFANA-STACK.md`
6. [ ] **Network — Transit Gateway vs VPC Lattice.** Connect the `dev` VPC to a
   throwaway "partner" VPC two ways — TGW (L3/L4, route tables) vs VPC Lattice
   (L7 service networking via the Gateway API, no route tables) — and compare.
   → `hands-on/test-plans/06-TEST-NETWORK-TRANSIT.md`
7. [ ] **AWS Organizations + Control Tower / Landing Zone.** What multi-account
   governance looks like for this repo's `dev`/`prod` split, and where Control
   Tower vs the Landing Zone Accelerator fit. ⚠️ design-first — see the doc's
   warning before running anything for real.
   → `hands-on/test-plans/07-TEST-AWS-ORG-LANDING-ZONE.md`

Add more rows here as new test ideas come up — this list is expected to grow.
