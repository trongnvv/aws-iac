# Observability on EKS — options & the platform's approach

Four ways to do observability on EKS, and where this repo lands.

## 1. Three tiers

| Tier | Role | Examples |
|---|---|---|
| Collect | On-cluster agent gathers metrics / logs / traces | OpenTelemetry Collector (ADOT), Grafana Alloy, Fluent Bit, Datadog Agent |
| Backend | Stores the data | Prometheus/Mimir, Loki, Tempo, Elasticsearch, CloudWatch |
| UI / Alert | Query, dashboard, alert | Grafana, Kibana, CloudWatch console, Datadog UI |

Datadog bundles all three. Grafana / Elastic are backend + UI. AWS offers both
CloudWatch (roll-your-own) and managed open source (AMP, AMG).

## 2. Four approaches compared

| | Datadog | Grafana stack (LGTM) | Elastic stack | AWS native |
|---|---|---|---|---|
| Components | SaaS all-in-one | Loki (logs) · Grafana · Tempo (traces) · Mimir/Prometheus (metrics) | Elasticsearch · Kibana · Beats/Elastic Agent · APM | CloudWatch Container Insights · X-Ray/Application Signals · AMP + AMG |
| Operations | Almost none | Self-host: medium. Grafana Cloud = SaaS option | Heavy (JVM, shards, storage). ECK operator or Elastic Cloud | Light, managed |
| Cost | Expensive; scales with hosts / GB logs / custom metrics | Cheap if self-hosted; logs/traces on S3 | Resource-hungry, storage-heavy | CloudWatch Logs ingest pricey; AMP/AMG reasonable |
| Data location | Leaves the account (Datadog) | In your AWS account | In account (if self-hosted) | In account |
| Strength | UX, correlation, fast setup | Flexible, open source, shared with on-prem | Deep log search, security/SIEM | AWS integration, IAM |

## 3. Choosing by situation

- **Small team, need speed, have budget, allowed to send data to SaaS** → Datadog
- **Data must stay in-account, minimal ops** → AMP + AMG (metrics), CloudWatch Logs or OpenSearch (logs)
- **Already on Prometheus/Grafana, want parity with on-prem** → Grafana LGTM
- **Deep log search / security analytics** → Elastic or OpenSearch

## 4. Common cloud-native pattern

- Collect with **OpenTelemetry** (ADOT or Alloy) → no backend lock-in
- Metrics: **AMP** · Logs: **Loki on S3** · Traces: **Tempo** · UI: **AMG**

## 5. What this repo does today, and the recommended path

Current state:
- `envs/<env>/02-platform/01-observability` = **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager) — metrics + UI, self-hosted, **ephemeral** (`emptyDir`).
- `envs/<env>/00-infra/05-observability-aws` = **AMP workspace + IAM** (Pod Identity roles for every collector + Grafana).
- **dev** wires the AWS-native pipeline (`enable_aws_native_pipeline`): kps Prometheus `remoteWrite` (allowlisted metrics) → AMP · `02-platform/07-observability-aws` = ADOT (OTLP → AMP + X-Ray) + Fluent Bit (→ CloudWatch Logs) · kps Grafana reads AMP/CloudWatch/X-Ray. The AMP workspace survives `teardown.sh`. Walkthrough: `hands-on/test-plans/03-TEST-OBSERVABILITY-AWS-NATIVE.md`.
- Gaps: no self-hosted logs/traces (Loki/Tempo — test 05), AMG unused (Grafana in kps instead), Prometheus not durable (see `REVIEW.md` #2).

Recommended per size (Grafana-LGTM-on-AWS, data in-account):

| Size | Metrics | Logs | Traces | UI |
|---|---|---|---|---|
| Small | kube-prometheus-stack (ephemeral) | — | — | bundled Grafana |
| Medium | kube-prometheus-stack + **PVC (gp3)** + retention | Loki on S3 (or CloudWatch) | — | bundled Grafana |
| Large | **AMP** (remoteWrite from ADOT/Alloy) | Loki on S3 | **Tempo** | **AMG** |

Collect with **OpenTelemetry (ADOT/Alloy)** from the start so the backend can change
without touching apps.

## 6. Compliance (regulated / finance)

- **SaaS** (Datadog, Grafana Cloud): verify **data-residency** rules and **PCI-DSS**
  scope before sending telemetry out of the account/country.
- **Mask/redact** sensitive fields **at the collector**, regardless of backend.

## 7. Multi-team (multi-tenant) — AMP workspace per team

AMP is **not** Mimir: there is no `X-Scope-OrgID` logical tenancy. AMP's isolation unit is the
**workspace**, so "one tenant per team" becomes **one AMP workspace per team**. AMP has no
per-workspace fee (billed per sample ingested/stored/queried), so N workspaces cost ≈ 1.

**Chosen approach (A) — workspace per team + one Grafana, org per team:**

| Old (Mimir) | This approach (AMP) |
|---|---|
| Mimir tenant (`X-Scope-OrgID`) per team | AMP **workspace per team** |
| write isolation via tenant header | **IAM** `aps:RemoteWrite` scoped to the team's workspace — each team's collector gets a Pod Identity role bound only to its workspace (hard isolation) |
| Grafana org per team + tenant datasource | Grafana **org per team**, each org a datasource → that team's workspace; map users → org + RBAC |

- **Write isolation = hard** (IAM per-team collector role).
- **Read isolation = Grafana org** (soft) when one shared Grafana — the same boundary the Mimir
  setup used. For hard read isolation, give each team its own Grafana/AMG workspace with an
  IAM role scoped to its AMP workspace (heavier).

**Alternatives considered:**
- **Keep Mimir self-hosted on EKS + S3** — if the `X-Scope-OrgID` tenant model (one backend, many
  tenants) matters, run Mimir yourself (S3 backend). Exact old model; you operate Mimir.
- **Single AMP + Grafana folders/labels** — cheapest to run but **no hard isolation** (AMP has no
  per-label access control; teams can query each other's metrics). Only for mutually-trusting teams.

→ Recommended: **A** — maps the old Mimir-tenant + Grafana-org + RBAC model onto AMP by swapping
*tenant → workspace*, and drops the Mimir ops burden. Choose Mimir-on-EKS only if header tenancy
is a hard requirement.
