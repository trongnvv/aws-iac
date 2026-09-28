# Test — observability, AWS-native (AMP)

Wires metrics into **Amazon Managed Prometheus** — the "Large" tier path from
`docs/OBSERVABILITY.md` §5. `modules/observability-aws` already has the IAM + pod
identity wiring gated by `enable_amp`; what's missing is an actual collector, since no
layer ships an ADOT/OTel collector yet. This test adds one by hand.

> 💸 AMP bills per sample ingested/stored. Set `enable_amp = false` again when done
> (§5) — it's `false` by default in both env presets.

## 0. Prereqs
Cluster up, `envs/<env>/00-infra/05-observability-aws` applied at least once (creates nothing while
`enable_amp` is false).

## 1. Turn on AMP for the env
Edit `envs/<env>/00-infra/05-observability-aws/*.tf`, add `enable_amp = true` to the
`observability_aws` module block (or pass `-var enable_amp=true`), then:
```bash
( cd envs/dev/00-infra/05-observability-aws && tofu apply )
AMP_URL=$(tofu output -raw amp_remote_write_url)
AMP_ARN=$(tofu output -raw amp_workspace_arn)
echo "$AMP_URL"
```
This also creates the `<cluster>-amp-write` IAM role + a **pod identity association**
already scoped to `namespace=opentelemetry, serviceAccount=adot-collector` — match
those names in step 2 or the collector won't get credentials.

## 2. Deploy an ADOT/OTel collector (not yet a layer — ad hoc for this test)
```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
kubectl create namespace opentelemetry
kubectl -n opentelemetry create serviceaccount adot-collector

helm install adot open-telemetry/opentelemetry-collector \
  --namespace opentelemetry \
  --set serviceAccount.create=false \
  --set serviceAccount.name=adot-collector \
  --set mode=deployment \
  --set-string config.exporters.prometheusremotewrite.endpoint="$AMP_URL" \
  --set-string config.exporters.prometheusremotewrite.auth.authenticator=sigv4auth \
  --set config.extensions.sigv4auth.region=ap-southeast-1 \
  --set config.extensions.sigv4auth.service=aps \
  --set config.service.extensions[0]=sigv4auth \
  --set config.service.pipelines.metrics.exporters[0]=prometheusremotewrite
```
The chart's default config already scrapes kubelet/cAdvisor + has a `prometheus`
receiver — this override only adds the AMP exporter on top; check
`kubectl -n opentelemetry logs deploy/adot-opentelemetry-collector` for `remote_write`
errors (401 = pod identity association mismatch from step 1).

## 3. Verify data landed in AMP
```bash
aws amp list-workspaces --alias "$(cd envs/dev/00-infra/01-eks && tofu output -raw cluster_name)-amp"
# quick query via the AMP query API (needs aps:QueryMetrics on your own identity, not the collector's role)
aws amp query-metrics --workspace-id "$(basename "$AMP_ARN")" \
  --query '{__name__="up"}' 2>/dev/null || echo "use a Grafana/AMG datasource instead — see §4"
```

## 4. View it — Amazon Managed Grafana (AMG)
Not modeled in Terraform here (console/CLI, one-off for the test):
1. AMG console → create workspace → authentication: **AWS IAM Identity Center** (or
   SAML) → grant yourself Admin.
2. In the workspace, **Data sources → Add → Amazon Managed Prometheus**, pick the
   `<cluster>-amp` workspace — AMG assumes its own service role, no extra IAM needed
   on your side.
3. Import a Kubernetes dashboard (e.g. ID `315` from grafana.com) and confirm the
   panels populate from the pods the ADOT collector scraped.

## 5. Cleanup
```bash
helm uninstall adot -n opentelemetry
kubectl delete ns opentelemetry
# then in envs/dev/00-infra/05-observability-aws/*.tf: enable_amp = false
( cd envs/dev/00-infra/05-observability-aws && tofu apply )
```
Delete the AMG workspace from the console too (it isn't Terraform-managed either).
