# Test — observability, Grafana stack (self-hosted)

Exercises what's already deployed: `envs/<env>/02-platform/01-observability` is
kube-prometheus-stack (Prometheus + Grafana + Alertmanager), in both env presets'
`L2` list. This test just proves it works end-to-end and reproduces the durability
gap called out in `docs/REVIEW.md` #2.

## 0. Prereqs
Cluster up, `envs/<env>/02-platform/00-argocd` + `envs/<env>/02-platform/01-observability` applied
(`cd envs/<env> && ./deploy.sh` does both).

## 1. Confirm it's running
```bash
kubectl -n monitoring get pods
kubectl -n monitoring get prometheus,alertmanager
```

## 2. Reach Grafana
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &
GRAFANA_PW=$(kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d)
echo "user=admin pass=$GRAFANA_PW  →  http://localhost:3000"
```
Open the default **Kubernetes / Compute Resources** dashboards — confirm node +
pod panels populate (proves the `kube-state-metrics` + node-exporter subcharts are
scraping).

## 3. Generate load to see it move
Reuse the REST demo from `01-TEST-INGRESS-GATEWAY-API.md` §1 (or any pod):
```bash
kubectl run load --image=williamyeh/hey --restart=Never --rm -it -- \
  -z 60s -c 20 http://whoami.default.svc.cluster.local
```
Watch the `whoami` Deployment's CPU/request-rate panels move in Grafana within the
scrape interval (default 30s).

## 4. Check Prometheus targets directly
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
```
Open `http://localhost:9090/targets` — everything should be `UP`; a `DOWN` target
here is usually a missing `ServiceMonitor`/`PodMonitor` label match.

## 5. Reproduce the durability gap (REVIEW.md #2)
```bash
kubectl -n monitoring delete pod -l app.kubernetes.io/name=prometheus
```
Prometheus comes back with an **empty TSDB** — the chart defaults to `emptyDir`. Fix
by adding a `gp3` PVC + retention to the helmfile values
(`envs/<env>/02-platform/01-observability/values*.yaml` — create if not present):
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources: { requests: { storage: 50Gi } }
```
```bash
( cd envs/<env>/02-platform/01-observability && helmfile apply )
```
Repeat the pod-delete test — data should now survive the restart (PVC persists).

## 6. Cleanup
```bash
pkill -f 'port-forward svc/kube-prometheus-stack'
kubectl delete pod load 2>/dev/null || true   # if the --rm hey pod didn't self-clean
```
Leave the stack running if it's still needed for other tests in the plan; otherwise
`helmfile destroy` in `envs/<env>/02-platform/01-observability`.
