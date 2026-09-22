# 09-observability-aws

Amazon Managed Prometheus (AMP) workspace + the Pod Identity role the metrics
collector (layer2 chart) assumes to remote-write metrics.

Gated by `enable_amp` (**default `false`** — AMP bills per sample). The collector
namespace/service-account are variables that must match the Helm release.
