# Architecture per size

Each size builds on the previous. `foundation` (S3 state + Route 53/ACM) is shared
by all. Diagrams are Mermaid — GitHub renders them inline.

**Colour legend:** 🟣 foundation · 🟠 edge/ingress · 🟢 EKS · 🟦 add-ons · 🔵 network (NAT/firewall/IGW) · 🟡 AWS managed services · ⚪ external.

Notes that apply to every size:
- Image pulls (ECR) and secret reads (Secrets Manager) go through **VPC interface
  endpoints** — private, skipping the NAT — not shown to keep the diagrams clean.
- Add-ons in the `layer1`/`layer2` boxes are Helm releases running as pods.

---

## Small (dev/lab)

Cluster + core add-ons, public API, single NAT, nothing paid.

```mermaid
flowchart TB
  internet([Internet]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    subgraph vpc["VPC · 3 AZ"]
      direction TB
      subgraph ingress["public subnets"]
        alb["ALB"]:::edge
      end
      subgraph eks["EKS cluster · public API"]
        direction LR
        cp["control plane"]:::eks
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · metrics-server · LBC<br/>cert-manager · external-secrets"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus"]:::add
      end
      subgraph egr["egress"]
        direction LR
        nat["NAT ×1"]:::net --> igw["IGW"]:::net
      end
    end
    svc["<b>AWS managed services</b><br/>ECR · Secrets Manager"]:::svc
  end
  internet --> alb --> nodes
  found -. DNS/TLS .-> alb
  nodes --> nat
  igw --> internet
  nodes -. images · secrets .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style ingress fill:#fff8ef,stroke:#fb8c00
  style egr fill:#eaf1fb,stroke:#3949ab
  style eks fill:#eaf6ea,stroke:#2e7d32
```

---

## Medium (staging)

Small **plus**: WAF at the edge, control-plane logging, secret encryption, network
policy, GuardDuty, backup, image scanning, and DNS/policy/event-scaling add-ons.

```mermaid
flowchart TB
  internet([Internet]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    subgraph vpc["VPC · 3 AZ"]
      direction TB
      subgraph ingress["public subnets · ingress"]
        direction TB
        waf["WAF"]:::edge --> alb["ALB"]:::edge
      end
      subgraph eks["EKS cluster · public API, restricted CIDRs"]
        direction LR
        cp["control plane"]:::eks
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · metrics-server · LBC · external-dns<br/>cert-manager · external-secrets · kyverno · keda · netpol"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus · velero"]:::add
      end
      subgraph egr["egress"]
        direction LR
        nat["NAT ×1"]:::net --> igw["IGW"]:::net
      end
    end
    svc["<b>AWS managed services</b><br/>CloudWatch · KMS · GuardDuty<br/>Secrets Manager · S3 backup · ECR"]:::svc
  end
  internet --> waf
  alb --> nodes
  found -. DNS/TLS .-> alb
  nodes --> nat
  igw --> internet
  nodes -. logs·secrets·backup·images·threat .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style ingress fill:#fff8ef,stroke:#fb8c00
  style egr fill:#eaf1fb,stroke:#3949ab
  style eks fill:#eaf6ea,stroke:#2e7d32
```

---

## Large (prod / regulated)

Medium **plus**: CloudFront/Shield, private API, per-AZ NAT, **egress Network
Firewall** (dedicated subnets + app-egress redirect), secondary pod CIDR, EFS,
Managed Prometheus, full security baseline, service mesh, API gateway, progressive
delivery, runtime security.

```mermaid
flowchart TB
  internet([Internet]):::ext
  partner([Exchange / partner]):::ext
  subgraph acct["AWS account · ap-southeast-1"]
    direction TB
    found["<b>foundation · shared</b><br/>S3 tfstate + lock · Route 53 + ACM"]:::fnd
    subgraph vpc["VPC · 3 AZ · primary + secondary CIDR"]
      direction TB
      subgraph ingress["public subnets · ingress"]
        direction TB
        cf["CloudFront + Shield"]:::edge --> waf["WAF"]:::edge --> alb["ALB"]:::edge
      end
      subgraph eks["EKS cluster · PRIVATE API"]
        direction LR
        cp["control plane"]:::eks
        nodes["nodes / pods"]:::eks
        l1["<b>layer1</b><br/>karpenter · LBC · external-dns · cert-manager<br/>external-secrets · kyverno · keda · dns-scale · netpol · metrics-server"]:::add
        l2["<b>layer2</b><br/>argocd · kube-prometheus · velero<br/>argo-rollouts · kubecost · Kong · Istio mTLS · Falco"]:::add
      end
      subgraph egr["egress · firewall subnets"]
        direction LR
        nfw["Network Firewall"]:::net --> nat["NAT ×3 · static EIP"]:::net --> igw["IGW"]:::net
      end
    end
    svc["<b>AWS managed services</b><br/>CloudWatch · KMS · Managed Prometheus · EFS<br/>S3 backup · ECR + Inspector<br/>GuardDuty · CloudTrail · Config · Security Hub"]:::svc
  end
  internet --> cf
  alb --> nodes
  found -. DNS/TLS .-> alb
  nodes -->|egress| nfw
  igw --> internet
  nat --> partner
  nodes -. logs·metrics·secrets·backup·images·audit .-> svc

  classDef ext fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc fill:#fffde7,stroke:#f9a825,color:#000
  style vpc fill:#f4f9ff,stroke:#1976d2
  style ingress fill:#fff8ef,stroke:#fb8c00
  style egr fill:#eaf1fb,stroke:#3949ab
  style eks fill:#eaf6ea,stroke:#2e7d32
```

> Egress path (large): pod → Network Firewall (domain allowlist) → NAT (static EIP)
> → IGW → internet / partner. The static EIP is what exchanges allowlist.
