# Architecture per size

Each size builds on the previous. `foundation` (S3 state + Route 53/ACM) is shared
by all. Diagrams are Mermaid — GitHub renders them inline.

**Colour legend:** 🟣 foundation · 🔵 network/VPC · 🟠 edge (ingress) · 🟢 EKS · 🟦 add-ons · 🟡 AWS managed services · ⚪ external.

---

## Small (dev/lab)

Cluster + core add-ons, public API, single NAT, nothing paid.

```mermaid
flowchart TB
  internet([Internet]):::ext

  subgraph acct["AWS account · ap-southeast-1"]
    direction TB

    subgraph found["foundation — run once, shared"]
      tfstate[("S3 tfstate<br/>+ DynamoDB lock")]:::fnd
      dns["Route 53 zone<br/>+ ACM cert"]:::fnd
    end

    ecr[("ECR")]:::svc

    subgraph vpc["VPC — 3 AZ"]
      igw["IGW"]:::net
      subgraph pub["public subnets"]
        alb["ALB"]:::edge
        nat["NAT ×1"]:::net
      end
      subgraph app["private-app subnets"]
        subgraph eks["EKS cluster · PUBLIC API"]
          cp["control plane"]:::eks
          nodes["system + Karpenter nodes"]:::eks
          addons["add-ons:<br/>karpenter · metrics-server · LB controller<br/>cert-manager · external-secrets<br/>argocd · kube-prometheus-stack"]:::add
        end
      end
    end
  end

  internet --> alb --> nodes
  dns -. DNS / TLS .-> alb
  nodes --> nat --> igw --> internet
  nodes -. pull images .-> ecr

  classDef ext  fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd  fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net  fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks  fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add  fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc  fill:#fffde7,stroke:#f9a825,color:#000
  style found fill:#f5f0fb,stroke:#7e57c2,stroke-dasharray:4 3
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style app fill:#f3faf3,stroke:#43a047
  style eks fill:#eaf6ea,stroke:#2e7d32
```

---

## Medium (staging)

Small **plus**: audit logging, secret encryption, network policy, image scanning,
WAF at the edge, GuardDuty, backup, DNS/policy/event-scaling add-ons.

```mermaid
flowchart TB
  internet([Internet]):::ext

  subgraph acct["AWS account · ap-southeast-1"]
    direction TB

    subgraph found["foundation"]
      tfstate[("S3 tfstate + lock")]:::fnd
      dns["Route 53 + ACM"]:::fnd
    end

    subgraph svcs["AWS managed services"]
      cw[("CloudWatch<br/>control-plane logs")]:::svc
      kms["KMS<br/>secret encryption"]:::svc
      gd["GuardDuty"]:::svc
      sm[("Secrets Manager")]:::svc
      s3b[("S3 — Velero backups")]:::svc
      ecr[("ECR — scan on push")]:::svc
    end

    subgraph vpc["VPC — 3 AZ"]
      igw["IGW"]:::net
      subgraph pub["public subnets"]
        waf["WAF"]:::edge
        alb["ALB"]:::edge
        nat["NAT ×1"]:::net
      end
      subgraph app["private-app subnets"]
        subgraph eks["EKS · public API, restricted CIDRs"]
          cp["control plane"]:::eks
          nodes["system + Karpenter nodes"]:::eks
          addons["add-ons: small<br/>+ external-dns · kyverno · keda<br/>+ velero · network-policy"]:::add
        end
      end
    end
  end

  internet --> waf --> alb --> nodes
  dns -. DNS / TLS .-> alb
  nodes --> nat --> igw --> internet
  cp --> cw
  cp --> kms
  gd -. threat detection .-> eks
  nodes -. Pod Identity .-> sm
  nodes --> s3b
  nodes -. images .-> ecr

  classDef ext  fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd  fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net  fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks  fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add  fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc  fill:#fffde7,stroke:#f9a825,color:#000
  style found fill:#f5f0fb,stroke:#7e57c2,stroke-dasharray:4 3
  style svcs fill:#fffef4,stroke:#f9a825,stroke-dasharray:4 3
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style app fill:#f3faf3,stroke:#43a047
  style eks fill:#eaf6ea,stroke:#2e7d32
```

---

## Large (prod / regulated)

Medium **plus**: private API, per-AZ NAT, **egress Network Firewall** (dedicated
subnets + app-egress redirect), secondary pod CIDR, EFS, full security baseline,
Managed Prometheus, service mesh, API gateway, progressive delivery, runtime security.

```mermaid
flowchart TB
  internet([Internet]):::ext
  partner([Exchange / partner<br/>allowlists our egress IP]):::ext

  subgraph acct["AWS account · ap-southeast-1"]
    direction TB

    subgraph found["foundation"]
      tfstate[("S3 tfstate + lock")]:::fnd
      dns["Route 53 + ACM"]:::fnd
    end

    subgraph svcs["AWS managed services"]
      cw[("CloudWatch")]:::svc
      kms["KMS"]:::svc
      amp[("Managed Prometheus")]:::svc
      efs[("EFS")]:::svc
      s3b[("S3 backups")]:::svc
      ecr[("ECR + Inspector")]:::svc
      sec["GuardDuty · CloudTrail<br/>Config · Security Hub"]:::svc
    end

    subgraph vpc["VPC — 3 AZ · primary + secondary CIDR"]
      igw["IGW"]:::net
      subgraph pub["public subnets"]
        cf["CloudFront + Shield"]:::edge
        waf["WAF"]:::edge
        alb["ALB"]:::edge
        nat["NAT ×3 · static EIP"]:::net
      end
      subgraph fw["firewall subnets"]
        nfw["Network Firewall<br/>domain allowlist"]:::net
      end
      subgraph app["private-app + pod subnets"]
        subgraph eks["EKS cluster · PRIVATE API"]
          cp["control plane"]:::eks
          nodes["system + Karpenter nodes / pods"]:::eks
          addons["add-ons: medium<br/>+ dns-scale · argo-rollouts · kubecost<br/>+ Kong · Istio mTLS · Falco"]:::add
        end
      end
    end
  end

  internet --> cf --> waf --> alb --> nodes
  dns -. DNS / TLS .-> alb
  nodes -->|egress| nfw --> nat --> igw --> internet
  nat --> partner
  cp --> cw
  cp --> kms
  cp --> amp
  nodes --> efs
  nodes --> s3b
  nodes -. images .-> ecr
  sec -. audit + threat .-> eks

  classDef ext  fill:#eceff1,stroke:#546e7a,color:#000
  classDef fnd  fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef net  fill:#e3f2fd,stroke:#1565c0,color:#000
  classDef edge fill:#fff3e0,stroke:#ef6c00,color:#000
  classDef eks  fill:#e8f5e9,stroke:#2e7d32,color:#000
  classDef add  fill:#e0f7fa,stroke:#00838f,color:#000
  classDef svc  fill:#fffde7,stroke:#f9a825,color:#000
  style found fill:#f5f0fb,stroke:#7e57c2,stroke-dasharray:4 3
  style svcs fill:#fffef4,stroke:#f9a825,stroke-dasharray:4 3
  style vpc fill:#f4f9ff,stroke:#1976d2
  style pub fill:#fff8ef,stroke:#fb8c00
  style fw fill:#eaf1fb,stroke:#3949ab
  style app fill:#f3faf3,stroke:#43a047
  style eks fill:#eaf6ea,stroke:#2e7d32
```

> Egress path (large): pod → Network Firewall (allowlist) → NAT (static EIP) → IGW
> → internet / partner. The static EIP is what exchanges allowlist.
