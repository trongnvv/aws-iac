# Architecture per size

Each size builds on the previous. `foundation` (S3 state + Route 53/ACM) is shared
by all. Diagrams are Mermaid — GitHub renders them inline.

## Reference infographic (dev/lab)

![EKS reference architecture](architecture.png)

> Diagram-as-code: `architecture.py` (Python [`diagrams`](https://diagrams.mingrammer.com/), one-shot
> infographic — topology + layered deploy + verify + cost). Regenerate:
> `uv run --native-tls --with diagrams python architecture.py` (needs graphviz: `brew install graphviz`;
> `--native-tls` so uv trusts the corporate CA). The Mermaid diagrams below are the per-size breakdown.

**Colour legend:** 🟣 foundation · 🟩 EKS control plane (AWS-managed) · 🟠 public subnets/edge · 🟢 private-app subnets · ⬜ private-isolated subnets · 🔵 network (NAT/firewall/IGW) · 🟦 add-ons · 🟡 AWS managed services · ⚪ external.

Accuracy notes (apply to every size):
- **Subnet tiers** (per AZ, built by `00-network`): **public** (tag `role/elb` — ALB, NAT),
  **private-app** (tags `internal-elb` + `karpenter.sh/discovery` — nodes/pods, plus
  the secondary-CIDR pod subnets), **private-isolated** (**no internet route** —
  reserved for RDS/ElastiCache, deployed by a separate stack). Large adds dedicated
  **firewall subnets**.
- The **EKS control plane is AWS-managed and runs outside your VPC**. Only the
  cross-account **EKS ENIs** and the **API endpoint** (public or private) touch your
  subnets — not the control-plane compute.
- **WAF** is a web ACL *attached* to the ALB (regional scope), not an inline hop.
- Image pulls (ECR) and secret reads (Secrets Manager) go through **VPC interface
  endpoints** — private, skipping the NAT.
- **CloudFront + Shield Advanced are not provisioned by this IaC** — add them at the
  edge if you need a CDN / DDoS tier.

---

## Small (dev/lab)

Cluster + core add-ons, public API, single NAT, nothing paid.

```mermaid
flowchart TB
  internet([Internet]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    cpane["<b>EKS control plane</b><br/>AWS-managed · outside your VPC<br/>public API endpoint"]:::mgmt
    subgraph vpc["VPC · 3 AZ"]
      direction TB
      igw["IGW"]:::net
      subgraph pub["public subnets · tag role/elb"]
        direction LR
        alb["ALB"]:::edge
        nat["NAT ×1"]:::net
      end
      subgraph app["private-app subnets · internal-elb + karpenter tags"]
        direction LR
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · metrics-server · LBC<br/>cert-manager · external-secrets"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus"]:::add
      end
      subgraph iso["private-isolated subnets · NO internet route"]
        isod["reserved: RDS · ElastiCache<br/>(separate stack)"]:::iso
      end
    end
    svc["<b>AWS managed services</b><br/>ECR · Secrets Manager"]:::svc
  end
  internet --> alb --> nodes
  found -. DNS / TLS .-> alb
  cpane -. cross-account ENIs · API .- nodes
  nodes --> nat --> igw --> internet
  nodes -. images · secrets .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef mgmt fill:#e8f5e9,stroke:#1b5e20,stroke-dasharray:5 3,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  classDef iso fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray:4 3,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style app fill:#eaf6ea,stroke:#2e7d32
  style iso fill:#fafafa,stroke:#9e9e9e
```

---

## Medium (staging)

Small **plus**: WAF on the ALB, control-plane logging, secret encryption, network
policy, GuardDuty, backup, image scanning, DNS/policy/event-scaling add-ons.

```mermaid
flowchart TB
  internet([Internet]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    cpane["<b>EKS control plane</b><br/>AWS-managed · outside your VPC<br/>public API · restricted CIDRs"]:::mgmt
    subgraph vpc["VPC · 3 AZ"]
      direction TB
      igw["IGW"]:::net
      subgraph pub["public subnets · tag role/elb"]
        direction LR
        alb["ALB"]:::edge
        waf["WAF web ACL"]:::edge
        nat["NAT ×1"]:::net
      end
      subgraph app["private-app subnets · internal-elb + karpenter tags"]
        direction LR
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · metrics-server · LBC · external-dns<br/>cert-manager · external-secrets · kyverno · keda · netpol"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus · velero"]:::add
      end
      subgraph iso["private-isolated subnets · NO internet route"]
        isod["reserved: RDS · ElastiCache<br/>(separate stack)"]:::iso
      end
    end
    svc["<b>AWS managed services</b><br/>CloudWatch · KMS · GuardDuty<br/>Secrets Manager · S3 backup · ECR"]:::svc
  end
  internet --> alb --> nodes
  waf -. attached .- alb
  found -. DNS / TLS .-> alb
  cpane -. cross-account ENIs · API .- nodes
  nodes --> nat --> igw --> internet
  nodes -. logs·secrets·backup·images·threat .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef mgmt fill:#e8f5e9,stroke:#1b5e20,stroke-dasharray:5 3,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  classDef iso fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray:4 3,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style app fill:#eaf6ea,stroke:#2e7d32
  style iso fill:#fafafa,stroke:#9e9e9e
```

---

## Large (prod / regulated)

Medium **plus**: private API, per-AZ NAT, **egress Network Firewall** (dedicated
subnets + app-egress redirect), secondary pod CIDR, EFS, Managed Prometheus, full
security baseline, service mesh, API gateway, progressive delivery, runtime security.

```mermaid
flowchart TB
  internet([Internet]):::ext
  partner([Exchange / partner]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    cpane["<b>EKS control plane</b><br/>AWS-managed · outside your VPC<br/>PRIVATE API endpoint"]:::mgmt
    subgraph vpc["VPC · 3 AZ · primary + secondary CIDR"]
      direction TB
      igw["IGW"]:::net
      subgraph pub["public subnets · tag role/elb"]
        direction LR
        alb["ALB"]:::edge
        waf["WAF web ACL"]:::edge
        nat["NAT ×3 · static EIP"]:::net
      end
      subgraph fw["firewall subnets"]
        nfw["Network Firewall"]:::net
      end
      subgraph app["private-app + pod subnets · internal-elb + karpenter tags"]
        direction LR
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · LBC · external-dns · cert-manager<br/>external-secrets · kyverno · keda · dns-scale · netpol · metrics-server"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus · velero<br/>argo-rollouts · kubecost · Kuma mTLS · Falco"]:::add
      end
      subgraph iso["private-isolated subnets · NO internet route"]
        isod["reserved: RDS · ElastiCache<br/>(separate stack)"]:::iso
      end
    end
    svc["<b>AWS managed services</b><br/>CloudWatch · KMS · Managed Prometheus · EFS<br/>S3 backup · ECR + Inspector<br/>GuardDuty · CloudTrail · Config · Security Hub"]:::svc
  end
  internet --> alb --> nodes
  waf -. attached .- alb
  found -. DNS / TLS .-> alb
  cpane -. cross-account ENIs · API .- nodes
  nodes -->|egress| nfw --> nat --> igw --> internet
  nat --> partner
  nodes -. logs·metrics·secrets·backup·images·audit .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef mgmt fill:#e8f5e9,stroke:#1b5e20,stroke-dasharray:5 3,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  classDef iso fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray:4 3,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style fw fill:#eaf1fb,stroke:#3949ab
  style app fill:#eaf6ea,stroke:#2e7d32
  style iso fill:#fafafa,stroke:#9e9e9e
```

> Egress path (large): pod → Network Firewall (domain allowlist) → NAT (static EIP)
> → IGW → internet / partner. The static EIP is what exchanges allowlist.
