# Test — observability, AWS-native (metrics · logs · traces)

All three pillars on AWS managed services, viewed in the **Grafana already shipped by
kube-prometheus-stack** (`02-platform/01-observability`, `grafana.trongnv.space`) — no
AMG (it needs IAM Identity Center, which pulls in Organizations).

AWS-native comes in **two flavors** that overlap; this test runs both, one after the other:

| | **Part A — Prometheus flavor** | **Part B — CloudWatch flavor** |
|---|---|---|
| Metrics | Prometheus `remoteWrite` + ADOT → **AMP** (PromQL) | **Container Insights** → CloudWatch Metrics |
| Logs | **Fluent Bit** → CloudWatch Logs | add-on's Fluent Bit → CloudWatch Logs |
| Traces | ADOT → **X-Ray** | **Application Signals** (auto-instrumentation → X-Ray) |
| Control plane | EKS control-plane logs → CloudWatch Logs (shared by A and B) | ← same |
| Portability | high — same collector/PromQL as the Grafana stack (test 05) | low — CloudWatch-only formats |

### By component — agent → routing → storage
Any observability pipeline splits into **agent** (collects at the source), **routing**
(receives, enriches, filters, authenticates, exports) and **storage** (keeps + serves
queries). Each cell says **what software runs, which image, who installs it, who owns its
config** — the last column then says plainly what is the same and what differs.

Install paths: Part A = Helm charts you pin and configure (helmfile in `02-platform/`).
Part B = **one EKS add-on** (`amazon-cloudwatch-observability`, AWS's packaging of the Helm
chart `aws-observability/amazon-cloudwatch-observability`) — AWS owns the manifests; you
only pass add-on config. Images below are from `chart 0.2.0` (A) / add-on `v6.7.0` (B).

| Component | Part A — Prometheus flavor | Part B — CloudWatch flavor | Same / different |
|---|---|---|---|
| **AGENT** | | | |
| App traces + metrics (instrumentation) | Nothing by default — the app must embed the **OTel SDK** (code change). Lab uses `telemetrygen` to fake an app. A6b: **community OTel Operator** (chart `open-telemetry/opentelemetry-operator`) injects the **upstream** Node.js SDK | **AWS fork of the OTel Operator** (`cloudwatch-agent-operator:3.7.0`, from the add-on) injects **AWS's ADOT SDK** (`adot-autoinstrumentation-node:v0.12.0`; also Java · Python · .NET) | **Same:** OpenTelemetry SDK, OTLP protocol, injection mechanism (mutating webhook + init container, same `instrumentation.opentelemetry.io/inject-*` annotation). **Different:** SDK build (upstream vs AWS), operator (community vs AWS fork), and A injects nothing unless you add A6b |
| Infra metrics | **Prometheus** (kube-prometheus-stack chart, `01-observability`) scrapes **kube-state-metrics** + **node-exporter** + kubelet/cAdvisor | **CloudWatch agent** (`cloudwatch-agent:1.300073.0`) DaemonSet — created by the add-on's operator from an `AmazonCloudWatchAgent` CR — reads kubelet/cAdvisor + kube API itself. No kube-state-metrics / node-exporter by default | **Different software** end to end |
| Container logs | **Fluent Bit**, image `aws-for-fluent-bit:3.2.1` · DaemonSet `aws-for-fluent-bit` in `logging` · installed by Helm chart `eks/aws-for-fluent-bit` (`07-observability-aws`) · config = your values · SA `aws-for-fluent-bit` | **Fluent Bit**, image `aws-for-fluent-bit:3.4.16` · DaemonSet `fluent-bit` in `amazon-cloudwatch` · installed by the add-on · config = fixed by AWS · SA `cloudwatch-agent` | **Same:** software, image repo (`public.ecr.aws/aws-observability/aws-for-fluent-bit`), input (`tail /var/log/containers`). **Different:** installer (your chart vs add-on), version, who owns config, namespace/SA |
| Node / OS logs | Not collected | Same `fluent-bit` DaemonSet as above, extra inputs: `systemd` (kubelet, containerd) + `tail` (`/var/log/messages`, `dmesg`) | **Different:** B only |
| Control-plane logs | No agent — EKS itself, `enable_control_plane_logging` in `01-eks` | No agent — EKS itself, same setting | **Same** |
| **ROUTING** | | | |
| App traces | **OpenTelemetry Collector**, **upstream** image `otel/opentelemetry-collector-contrib` (release named `adot`, but **not** AWS's ADOT collector image) · Deployment in `opentelemetry` · chart `open-telemetry/opentelemetry-collector` · pipeline you write: `otlp → batch → awsxray` | **CloudWatch agent** (same DaemonSet as infra metrics; it embeds OTel Collector components) · receives OTLP from the injected SDK → X-Ray, and derives Application Signals RED metrics · config by AWS | **Same:** OTLP in, X-Ray out. **Different:** software (standalone OTel Collector vs CloudWatch agent), config owner, B adds App Signals |
| App metrics | Same OTel Collector: `otlp → prometheusremotewrite` (SigV4) → AMP | CloudWatch agent → Application Signals metrics → CloudWatch Metrics | **Different** software and destination |
| Infra metrics | Prometheus `remoteWrite` (SigV4) → AMP (full set; **you can filter** with an optional `writeRelabelConfigs` keep-list) | CloudWatch agent writes **EMF log events** to `/aws/containerinsights/eks-dev/performance` → CloudWatch extracts metrics. No filter knob | **Different** mechanism |
| Logs | Inside Fluent Bit: `kubernetes` filter (pod metadata) → `cloudwatch_logs` output → **1 group** `/eks/eks-dev/containers` | Inside Fluent Bit: `kubernetes` filter → `cloudwatch_logs` output → **3 groups** `application` · `dataplane` · `host` | **Same:** plugins and flow. **Different:** log-group layout |
| Auth | EKS Pod Identity · **3 roles / 4 associations**: `amp-write` (OTel Collector + Prometheus), `fluent-bit`, `grafana-read` — created by OpenTofu (`05-observability-aws`) | EKS Pod Identity · **1 role** (`cloudwatch-agent`) shared by CloudWatch agent **and** Fluent Bit (both run as SA `cloudwatch-agent`) — association created by `aws eks create-addon` | **Same:** mechanism. **Different:** one role per component vs one shared role |
| **STORAGE** | | | |
| Metrics | **AMP** — Prometheus TSDB, query with PromQL | **CloudWatch Metrics** — namespaces `ContainerInsights` / `ApplicationSignals`, query with metric math | **Different** service |
| Logs | **CloudWatch Logs** — retention 3 days (set in values) | **CloudWatch Logs** — retention **never expire** by default | **Same** service. **Different:** groups + retention |
| Traces | **X-Ray** | **X-Ray** (+ Application Signals service / SLO views on top) | **Same** service |

**Bottom line:** logs (agent, routing, store) and the trace store are the same in A and B —
only packaging differs. What really differs is the **metrics path end to end**
(Prometheus → AMP vs CloudWatch agent → EMF → CloudWatch Metrics) and **who instruments +
routes app telemetry** (you: SDK + your OTel Collector config vs the add-on, automatically).

> 💸 AMP, CloudWatch Logs, Container Insights and X-Ray all bill per volume. Run each part
> and its cleanup **the same day**.

## 0. The service map

| Layer | Service | Role |
|---|---|---|
| Collect | **ADOT** (OTel Collector, contrib image) | receives OTLP from apps → AMP + X-Ray |
| | **Fluent Bit** | DaemonSet tailing `/var/log/containers` → CloudWatch Logs |
| | **CloudWatch Observability add-on** | CloudWatch agent + Fluent Bit + OTel operator, one EKS add-on |
| | kube-state-metrics · node-exporter | k8s object + node metrics (already in kube-prometheus-stack) |
| Metrics | **AMP** | Prometheus-compatible storage, PromQL |
| | **CloudWatch Metrics / Container Insights** | prebuilt cluster/node/pod metrics |
| Logs | **CloudWatch Logs** + Logs Insights | app logs + EKS control-plane logs |
| Traces | **X-Ray** | trace storage + service map |
| | **Application Signals** | APM on top: per-service RED metrics, SLOs, trace↔log links |
| View | Grafana (existing) | datasources: AMP · CloudWatch · X-Ray |
| Alert | AMP rules / CloudWatch Alarms → **SNS** | (stretch — not in this test) |
| Auth | **EKS Pod Identity** | one IAM role per collector ServiceAccount |

```mermaid
flowchart LR
  subgraph EKS["EKS cluster eks-dev"]
    subgraph A["Part A — Prometheus flavor"]
      PROM["kube-prometheus-stack<br/>Prometheus"]
      APP["app / telemetrygen"]
      ADOT["ADOT collector<br/>ns opentelemetry"]
      FB["Fluent Bit DS<br/>ns logging"]
    end
    subgraph B["Part B — CloudWatch flavor"]
      CWA["CloudWatch agent DS"]
      FB2["add-on Fluent Bit DS"]
      HE["hello-express<br/>auto-instrumented Node.js"]
    end
    GRAF["Grafana (kps)"]
    PI(["EKS Pod Identity<br/>IAM role per SA"])
  end
  CP["EKS control plane"]

  subgraph AWS["AWS managed services"]
    AMP[("AMP")]
    XRAY[("X-Ray")]
    CWL[("CloudWatch Logs")]
    CWM[("CloudWatch Metrics<br/>ContainerInsights")]
    APPSIG["Application Signals<br/>RED · SLO"]
  end

  PROM -- "remoteWrite SigV4" --> AMP
  APP -- OTLP --> ADOT
  ADOT -- metrics --> AMP
  ADOT -- traces --> XRAY
  FB -- "/eks/eks-dev/containers" --> CWL
  CP -- "control-plane logs" --> CWL
  CWA --> CWM
  FB2 -- "/aws/containerinsights/..." --> CWL
  HE -- "OTLP traces + metrics" --> CWA
  CWA --> XRAY
  XRAY --> APPSIG

  AMP --> GRAF
  CWL --> GRAF
  CWM --> GRAF
  XRAY --> GRAF
  PI -. credentials .-> ADOT & PROM & FB & CWA & GRAF
```

## 1. Prereqs (both parts)
```bash
cd ~/src/github/trongnvv/aws-iac/eks     # every command below runs from the repo root
envs/dev/deploy.sh                        # cluster + 02-platform (kps, argocd)
kubectl -n monitoring get pods                                  # kps healthy
```
hello-express deployed per `hands-on/DEPLOY-HELLO-EXPRESS.md` (Part B needs a Node.js app).

### 1.1 Control-plane logs (shared)
In `envs/dev/00-infra/01-eks/main.tf`, `module "eks"` block: `enable_control_plane_logging = true`.
```bash
( cd envs/dev/00-infra/01-eks && tofu apply )
aws logs describe-log-groups --log-group-name-prefix /aws/eks/eks-dev
```
✅ `/aws/eks/eks-dev/cluster` exists; streams `kube-apiserver-audit-*` fill within minutes.

---

# Part A — Prometheus flavor

Part A is **in code**, deployed by `envs/dev/deploy.sh` like any other layer:

| Piece | Where |
|---|---|
| AMP workspace + IAM roles + Pod Identity (ADOT, Prometheus, Fluent Bit, Grafana) | `modules/observability-aws` · `envs/dev/00-infra/05-observability-aws` (`enable_amp`) |
| Infra metrics → AMP (`remoteWrite`, full set) · Grafana SigV4 + AMP/CloudWatch/X-Ray datasources | `envs/dev/02-platform/01-observability/values.yaml` |
| ADOT collector · Fluent Bit | `envs/dev/02-platform/07-observability-aws/` |

`teardown.sh` destroys only the IAM side of `05-observability-aws` and **keeps the AMP
workspace** (idle ≈ $0), so its ID — hardcoded in the Helm values — stays valid across
redeploys. It also lists EBS volumes orphaned by PVCs at the end.

## A1. Wire the AMP URL (once)
The §1 deploy created the workspace, but the Helm values still hold `ws-REPLACE-ME`
(remote-write just errors until fixed):
```bash
( cd envs/dev/00-infra/05-observability-aws && tofu output -raw amp_workspace_arn )   # …:workspace/ws-xxxx
WS=ws-xxxx                                                                            # from the line above
grep -rl ws-REPLACE-ME envs/dev/02-platform | xargs sed -i "s/ws-REPLACE-ME/$WS/"      # 3 places, 2 files
git diff --stat envs/dev/02-platform                                                  # commit it — stable from now on
envs/dev/deploy.sh 02-platform
```
✅ Checks:
```bash
aws eks list-pod-identity-associations --cluster-name eks-dev \
  --query 'associations[].[namespace,serviceAccount]' --output table
```
4 rows: `opentelemetry/adot-collector` · `monitoring/kube-prometheus-stack-prometheus` ·
`monitoring/kube-prometheus-stack-grafana` · `logging/aws-for-fluent-bit`.
Pods started **before** their association existed have no credentials →
`kubectl -n <ns> rollout restart …` fixes it.

## A2. Metrics — infra: Prometheus `remoteWrite` → AMP
Infra metrics (kube-state-metrics, node-exporter, kubelet/cAdvisor) are already scraped by
kps Prometheus, so they're forwarded, not scraped twice. The **full** set is sent — no allowlist.
⚠️ AMP bills per sample, and the full kps set is ~50–100k series (≈ $13–26/day). If cost matters,
re-add a `writeRelabelConfigs` keep-list in `02-platform/01-observability/values.yaml` to trim to
the metrics you actually query.
```bash
kubectl -n monitoring logs prometheus-kube-prometheus-stack-prometheus-0 -c prometheus | grep -iE "remote|403|401"
```
✅ No `403`/`401`. Grafana → Explore → **AMP** → `up` returns the same targets as the in-cluster
Prometheus; `node_disk_io_time_seconds_total` now returns data too (nothing filtered out).

## A3. Metrics (app) + traces — ADOT → AMP + X-Ray
ADOT receives OTLP on `adot-opentelemetry-collector.opentelemetry:4317` (gRPC) / `:4318`
(HTTP). Generate telemetry — no app code needed, `telemetrygen` speaks OTLP:
```bash
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest
OTLP=adot-opentelemetry-collector.opentelemetry:4317
kubectl run tg-traces  --rm -it --restart=Never --image=$TG -- \
  traces  --otlp-endpoint=$OTLP --otlp-insecure --duration=60s --rate=5 --service=demo-checkout
kubectl run tg-metrics --rm -it --restart=Never --image=$TG -- \
  metrics --otlp-endpoint=$OTLP --otlp-insecure --duration=60s --service=demo-checkout
```
✅ Checks:
```bash
kubectl -n opentelemetry logs deploy/adot-opentelemetry-collector | grep -iE "error|denied"   # empty
aws xray get-trace-summaries --start-time $(date -d '-10 min' +%s) --end-time $(date +%s) \
  --query 'length(TraceSummaries)'                                                          # > 0
```
Grafana → Explore → **AMP** → `{service_name="demo-checkout"}`; → **X-Ray** → Trace List /
Service Map shows `demo-checkout`.

## A4. Logs — Fluent Bit → CloudWatch Logs

> ⏭️ **Optional checks.** The log path is the same mechanism in both parts (Fluent Bit
> DaemonSet tailing `/var/log/containers` → CloudWatch Logs); only the packaging differs
> (config ownership, log groups, retention). A and B really differ on **metrics** (AMP/PromQL
> vs CloudWatch Metrics) and **traces** (manual OTLP vs auto-instrumentation). Short on time →
> skip this step and look at logs only in Part B (B3).

Fluent Bit writes every container's stdout/stderr to `/eks/eks-dev/containers` (3-day
retention; IAM scoped to `/eks/eks-dev/*`).
```bash
kubectl run logger --image=busybox --restart=Never -- \
  sh -c 'i=0; while true; do echo "order=$i status=ok"; i=$((i+1)); sleep 2; done'
aws logs tail /eks/eks-dev/containers --since 5m --filter-pattern order | head
```
✅ `order=N status=ok` lines in CloudWatch. Grafana → Explore → **CloudWatch** → *Logs* →
log group `/eks/eks-dev/containers`, Logs Insights query:
`fields @timestamp, log | filter log like /order=/ | sort @timestamp desc | limit 20`.
Same panel, log group `/aws/eks/eks-dev/cluster` → the control-plane audit log from §1.1.

## A5. One dashboard, three pillars
Build a Grafana dashboard with:
1. **AMP** — `sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))`
2. **CloudWatch Logs** — the Logs Insights query from A4
3. **X-Ray** — Service Map for `demo-checkout`

Gap to notice: nothing links a log line to its trace — the app must write `trace_id` into its
logs and the datasources must be told about it. Part B shows AWS doing that for you; test 05
shows doing it yourself with Loki ↔ Tempo.

## A6. Questions to answer
- Why does Pod Identity need the exact `namespace/serviceAccount`? What happens with a typo?
- Why `remoteWrite` from Prometheus for infra but ADOT for app telemetry?
- What does `resource_to_telemetry_conversion` change in the stored series?
- AMP vs self-hosted Prometheus/Mimir: cost model, retention, who's on call?

## A6b. Stretch — hello-express through Part A (same real app as B4)
Part A uses telemetrygen; Part B uses a real, auto-instrumented app. To compare both on
**the same app**, inject the OTel Node.js agent into hello-express with the community
**OpenTelemetry Operator** and point it at the A3 ADOT collector. (Alternative: add the OTel
SDK to hello-express's code — a code change, not covered here.)

> ⚠️ Run this **before Part B**. The CloudWatch add-on ships its own operator that reacts to
> the same `instrumentation.opentelemetry.io/inject-nodejs` annotation — two operators =
> two mutating webhooks fighting over the same pods.

Needs ADOT from A3 still running and cert-manager (`01-addons/04-cert-manager`) for the
operator's webhook certificate.
```bash
helm install otel-operator open-telemetry/opentelemetry-operator \
  -n opentelemetry-operator-system --create-namespace \
  --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib
kubectl -n opentelemetry-operator-system rollout status deploy/otel-operator-opentelemetry-operator

kubectl apply -f - <<'EOF'
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: to-adot
  namespace: dev
spec:
  exporter:
    endpoint: http://adot-opentelemetry-collector.opentelemetry:4318   # Node.js agent speaks OTLP/HTTP
  propagators: [tracecontext, baggage]
  sampler:
    type: parentbased_traceidratio
    argument: "1"                                                       # sample everything (lab)
EOF

# Namespace annotation — hello-express is Argo CD-managed (selfHeal) and its chart has no podAnnotations.
kubectl annotate ns dev instrumentation.opentelemetry.io/inject-nodejs="true"
kubectl -n dev rollout restart deploy
kubectl -n dev get pods -o custom-columns='POD:.metadata.name,INIT:.spec.initContainers[*].name' | grep hello
```
✅ An `opentelemetry-auto-instrumentation-nodejs` init container on the hello-express pods.

Generate traffic (same loop as B4), then:
- Grafana → **X-Ray** → Service Map shows `hello-express` (real HTTP server spans, not
  telemetrygen's fake ones).
- Grafana → **AMP** → `{service_name="hello-express"}` — the agent's HTTP metrics.

Compare with B4 later on the same app: what Application Signals gives on top (RED per
operation, SLOs, trace ↔ log links) vs what you'd have to build in Grafana yourself here.

## A7. Alerting — replaces Grafana OnCall (routing to multi-team channels)
**Wired in IaC** — `modules/observability-aws/5-alerting.tf`, enabled in dev
(`00-infra/05-observability-aws`, `enable_alerting = true`). The Grafana-OnCall model (rules →
route by label → team channels, with on-call schedules/escalation) maps to AWS-native like this:

| OnCall did | AWS-native |
|---|---|
| Alert rules | **AMP rule groups** (PrometheusRule syntax) — AMP managed, evaluates them |
| Route to the right team's channel | **AMP AlertManager** `route` tree — match label `team`/`severity` → per-team receiver |
| Deliver to Slack/Teams | receiver → **SNS** (one topic per team) → **AWS Chatbot** (Amazon Q in chat) |
| On-call schedule + escalation (paging) | **AWS Systems Manager Incident Manager** (AWS-native) *or* PagerDuty/Opsgenie (SaaS, closest to OnCall UX) |

Flow:
```
AMP rules → AMP AlertManager (route by team/severity label)
  → SNS (1 topic/team) → AWS Chatbot → team Slack/Teams       (notify)
                       → Incident Manager / PagerDuty          (on-call schedule + escalate + page)
```

**Multi-team routing** = the AlertManager `route` tree: top route branches on the `team` label,
one child route per team → receiver = that team's SNS topic/webhook. Same label-routing idea OnCall
used. With the multi-tenant module (`modules/observability-aws-multitenant`, workspace-per-team),
**each team's AMP workspace carries its own rules + AlertManager config** → routes straight to that
team's channel; no shared routing to untangle.

What the IaC creates (`5-alerting.tf`, gated by `enable_alerting`):
- **AMP rule groups** — authored as plain YAML in `00-infra/05-observability-aws/rules/*.yaml` (bare
  `groups:` schema, like a PrometheusRule body), shipped via `file()`. Add an alert = drop a YAML file.
- **AMP Alert Manager** (`aws_prometheus_alert_manager_definition`) — route tree: `team` label →
  `sns-<team>`, fallthrough → `sns-default`.
- **SNS topic per team + `default`** (+ topic policy letting `aps.amazonaws.com` publish).
- **AWS Chatbot** (Slack) per team — only when `alert_slack_workspace_id` + `alert_teams[*].slack_channel_id` are set.

Deploy: it's in code — `enable_alerting = true` in `00-infra/05-observability-aws`, rules in
`rules/*.yaml`. `( cd envs/dev/00-infra/05-observability-aws && tofu apply )` creates the SNS topics,
rule groups and the Alert Manager definition.

Verify:
```bash
WS=$(cd envs/dev/00-infra/05-observability-aws && tofu output -raw amp_workspace_arn | sed 's#.*/##')
aws amp list-rule-groups-namespaces --workspace-id "$WS"          # rule group landed
aws amp describe-alert-manager-definition --workspace-id "$WS"    # route tree + sns receivers
aws sns list-topics --query "Topics[?contains(TopicArn,'eks-dev-alerts')].TopicArn" --output text
# end-to-end SNS leg: subscribe + publish a test (default topic)
DEF=$(aws sns list-topics --query "Topics[?ends_with(TopicArn,'eks-dev-alerts-default')].TopicArn" --output text)
aws sns subscribe --topic-arn "$DEF" --protocol email --notification-endpoint you@example.com   # confirm via email
aws sns publish --topic-arn "$DEF" --subject "test" --message "hello from alerting"
```
✅ rule-group + alert-manager exist in AMP; the test publish arrives at the subscribed endpoint.
A real rule→route path (e.g. `TargetDown`) fires after its `for:` window — slower, so the SNS
publish above is the quick plumbing check.

Manual / notes:
- 🖐️ **Chatbot Slack**: authorize the Slack workspace once in the AWS Chatbot console → pass its
  workspace id as `alert_slack_workspace_id`, each channel id in `alert_teams`. Chatbot's API is
  **us-east-1** — add a us-east-1 provider alias in the env root if apply complains.
- ⚠️ **team routing** needs a `team` label on the series — add it via remote-write relabeling
  (namespace → team); without it, alerts go to `sns-default`.
- On-call (not in IaC): subscribe **Incident Manager** or **PagerDuty** to the same SNS topic.

Alternative (Grafana-centric, closer to the old setup): skip AMP AlertManager and use the Grafana
you deploy — **Grafana unified alerting** (rules) + **notification policies** (route by label →
per-team contact point: Slack/SNS/PagerDuty). One place for dashboards + alerts; but it's Grafana
config, not the AMP-managed path.

## A8. Cleanup Part A
Part A is part of the dev layers, so the normal path is **`envs/dev/teardown.sh`** (keeps
the AMP workspace, drops the IAM). To stop paying for ingestion while keeping the cluster:
```bash
# A6b (if run) — remove first so Part B's add-on doesn't meet a second operator
kubectl annotate ns dev instrumentation.opentelemetry.io/inject-nodejs- 2>/dev/null
kubectl -n dev delete instrumentation to-adot 2>/dev/null
helm uninstall otel-operator -n opentelemetry-operator-system 2>/dev/null && \
  kubectl delete ns opentelemetry-operator-system
kubectl -n dev rollout restart deploy                                  # drop the injected agent

kubectl delete pod logger
( cd envs/dev/02-platform/07-observability-aws && helmfile destroy )   # ADOT + Fluent Bit
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus \
  --type=json -p '[{"op":"remove","path":"/spec/remoteWrite"}]'       # until next helmfile apply
aws logs delete-log-group --log-group-name /eks/eks-dev/containers
```
Part B reuses the Grafana read role and datasources — keep `05-observability-aws` applied.

---

# Part B — CloudWatch flavor (Container Insights + Application Signals)

**Path A (Prometheus/AMP) is the chosen rollout.** Part B (CloudWatch) is kept **collapsed as a
reference** — the A-vs-B trade-off is in the table below. Expand only if revisiting the CloudWatch route.

| | Part A (Prometheus) — chosen | Part B (CloudWatch) |
|---|---|---|
| Setup effort | IAM ×4, 2 charts, values edits | 1 IAM role + 1 add-on + 1 annotation |
| Query language | PromQL (portable) | CloudWatch metrics math / Logs Insights |
| App instrumentation | you add OTel SDK (or telemetrygen) | auto-injected (Java/Python/.NET/Node.js) |
| Trace ↔ log | DIY | built in (App Signals) |
| Lock-in | low | high |

> Run after A8 (cleanup) — the add-on ships its own Fluent Bit; running both doubles log cost.

<details>
<summary><b>Part B — CloudWatch flavor: full steps (reference, click to expand)</b></summary>

## B1. IAM for the CloudWatch agent
Add to `modules/observability-aws` (new var `enable_container_insights`, default `false`):
```hcl
resource "aws_iam_role" "cloudwatch_agent" {
  count              = var.enable_container_insights ? 1 : 0
  name               = "${var.cluster_name}-cloudwatch-agent"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = var.enable_container_insights ? toset([
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
  ]) : toset([])
  role       = aws_iam_role.cloudwatch_agent[0].name
  policy_arn = each.value
}

output "cloudwatch_agent_role_arn" {
  value = var.enable_container_insights ? aws_iam_role.cloudwatch_agent[0].arn : null
}
```
Set `enable_container_insights = true` in the dev root's module block and re-export the
output there. No association here — the add-on creates it (B2); declaring both conflicts.
`local.pod_identity_trust` is defined in `2-amp.tf`.
```bash
cd envs/dev/00-infra/05-observability-aws
tofu apply
CW_ROLE=$(tofu output -raw cloudwatch_agent_role_arn)
cd -
```

## B2. Install the add-on + turn on Application Signals
```bash
aws application-signals start-discovery            # one-time per account/region (service-linked role)
aws eks create-addon --cluster-name eks-dev --addon-name amazon-cloudwatch-observability \
  --pod-identity-associations serviceAccount=cloudwatch-agent,roleArn=$CW_ROLE
aws eks wait addon-active --cluster-name eks-dev --addon-name amazon-cloudwatch-observability
kubectl -n amazon-cloudwatch get pods
```
✅ `cloudwatch-agent-*` + `fluent-bit-*` DaemonSet pods and the operator are `Running`.

## B3. Container Insights (metrics + logs)
```bash
aws cloudwatch list-metrics --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value=eks-dev --query 'length(Metrics)'
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/eks-dev \
  --query 'logGroups[].logGroupName'
```
✅ Metrics count > 0 (takes ~5 min); log groups `application` · `dataplane` · `host` · `performance`.
Console: CloudWatch → **Container Insights** → cluster `eks-dev` → drill into a pod.
Grafana → Explore → **CloudWatch** → namespace `ContainerInsights`, metric `pod_cpu_utilization`.

## B4. Application Signals (traces + APM) on hello-express
The add-on's operator injects the OTel Node.js agent when a pod carries
`instrumentation.opentelemetry.io/inject-nodejs: "true"`. hello-express is owned by
Argo CD (`selfHeal: true`) and its chart has no `podAnnotations`, so annotate the
**namespace** (not managed by Argo) and restart:
```bash
kubectl annotate ns dev instrumentation.opentelemetry.io/inject-nodejs="true"
kubectl -n dev rollout restart deploy
kubectl -n dev get pods -o custom-columns='POD:.metadata.name,INIT:.spec.initContainers[*].name' | grep hello
```
✅ An `opentelemetry-auto-instrumentation-nodejs` init container is present. (If not, the
namespace annotation isn't honored by this add-on version → add `podAnnotations` to
`helm-chart-template/app` and set it in `apps/hello-express/dev/values.yaml` instead.)

Generate traffic, then look:
```bash
HOST=$(kubectl -n dev get ingress -o jsonpath='{.items[0].spec.rules[0].host}')
for i in $(seq 200); do curl -s -o /dev/null https://$HOST/; done
```
Console: CloudWatch → **Application Signals → Services** → `hello-express`: latency / error /
volume, operations, dependencies; open a trace → **related logs** (correlated automatically).
Create an SLO: *latency p99 < 300 ms, 99% over 1 day* — the AWS-native version of the
SLO/error-budget idea.

## B5. Cleanup Part B
```bash
kubectl annotate ns dev instrumentation.opentelemetry.io/inject-nodejs-
kubectl -n dev rollout restart deploy
aws eks delete-addon --cluster-name eks-dev --addon-name amazon-cloudwatch-observability
for g in application dataplane host performance; do
  aws logs delete-log-group --log-group-name /aws/containerinsights/eks-dev/$g; done
# enable_container_insights = false in the dev root, then:
( cd envs/dev/00-infra/05-observability-aws && tofu apply )
```
Control-plane logs (§1.1): set `enable_control_plane_logging = false` back, `tofu apply` in
`01-eks`, and delete `/aws/eks/eks-dev/cluster` if not needed.

</details>
