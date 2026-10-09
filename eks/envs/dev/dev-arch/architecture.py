"""EKS env=dev — AWS infrastructure architecture (ap-southeast-1).

Drawn only from relations.yaml (built from envs/dev/00-infra/*/main.tf + modules/*).
Run:  uv run --with diagrams --with pillow --with pyyaml python architecture.py  → architecture.png
Content is data (CARDS/EDGES); style lives in the helpers.
"""
import os
import subprocess
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EKS, EC2ContainerRegistry, EC2Instance
from diagrams.aws.cost import CostExplorer
from diagrams.aws.devtools import XRay
from diagrams.aws.general import InternetAlt1, Users
from diagrams.aws.integration import Eventbridge, SimpleNotificationServiceSns, SimpleQueueServiceSqs
from diagrams.aws.management import AmazonManagedPrometheus, Cloudwatch, Cloudtrail
from diagrams.aws.network import (
    ElbApplicationLoadBalancer, Endpoint, InternetGateway, NATGateway, PrivateSubnet,
    PublicSubnet, Route53, VPC,
)
from diagrams.aws.security import CertificateManager, IAMRole, SecretsManager, WAF
from diagrams.aws.storage import S3

# ── style ────────────────────────────────────────────────────────────────────────────────────────
FONT, BOLD, MONO = "Noto Sans", "Noto Sans Bold", "DejaVu Sans Mono"
CANVAS, PANEL, NAVY, INK, MUTED = "#EEF1F5", "#FFFFFF", "#1F3A68", "#1B2433", "#5F6B7A"
ROLE = {  # (stroke/pill, card tint)
    "main":   ("#2563EB", "#F3F7FF"),
    "hub":    ("#7C3AED", "#F7F3FF"),
    "shared": ("#16A34A", "#F2FBF5"),
    "opt":    ("#EA7A0C", "#FFF8F0"),
    "deny":   ("#DC2626", "#FFF3F3"),
    "mgmt":   ("#64748B", "#F6F7F9"),
}
# edge kind → (role color, dashed, dotted)
EK = {
    "sync":    ("main",   False, False),
    "async":   ("hub",    True,  False),
    "data":    ("shared", False, False),
    "network": ("mgmt",   False, False),   # navy-ish; use NAVY below
    "control": ("mgmt",   True,  False),
    "deny":    ("deny",   True,  False),
}
EDGE_NAVY = "#1F3A68"
_BASE = Path(diagrams.__file__).resolve().parent.parent


def icon(cls):
    return str(_BASE / cls._icon_dir / cls._icon)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def txt(s, size=12, color=INK, face=FONT, bold=False):
    s = f"<B>{esc(s)}</B>" if bold else esc(s)
    return f'<FONT FACE="{face}" POINT-SIZE="{size}" COLOR="{color}">{s}</FONT>'


def img_cell(src, size=38, rowspan=1):
    return (f'<TD ROWSPAN="{rowspan}" FIXEDSIZE="TRUE" WIDTH="{size}" HEIGHT="{size}" VALIGN="MIDDLE">'
            f'<IMG SRC="{src}" SCALE="TRUE"/></TD>')


def pill(s, color, size=11):
    return (f'<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="4" CELLSPACING="0" STYLE="rounded" BGCOLOR="{color}">'
            f'<TR><TD>{txt(" " + s + " ", size, "white", BOLD)}</TD></TR></TABLE>')


def tag(s, color):
    return (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="{color}" CELLPADDING="1" CELLSPACING="0" STYLE="rounded">'
            f'<TR><TD>{txt(s, 8, color, BOLD)}</TD></TR></TABLE>')


def card(title, lines, role="main", ic=None, tagged=None, width=250):
    """White rounded card: icon left + bold title + ≤2 muted fact lines. Whole card = the node."""
    stroke, _ = ROLE[role]
    n = 1 + len(lines)
    left = img_cell(ic, rowspan=n) if ic else ""
    head = txt(title, 12, INK, BOLD)
    if tagged:
        head = (f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0"><TR><TD>{head}</TD>'
                f'<TD WIDTH="6"></TD><TD>{tag(tagged, ROLE["opt"][0])}</TD></TR></TABLE>')
    body = "".join(f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">{txt(l, 9, MUTED)}</TD></TR>' for l in lines)
    border = stroke if role in ("opt", "deny", "hub") else "#D5DBE3"
    return (f'<<TABLE BORDER="1" CELLBORDER="0" COLOR="{border}" STYLE="rounded" BGCOLOR="white" '
            f'CELLPADDING="6" CELLSPACING="2" WIDTH="{width}">'
            f'<TR>{left}<TD ALIGN="LEFT" WIDTH="{width - 54}">{head}</TD></TR>{body}</TABLE>>')


def node(label_html, **attrs):
    return Node(label_html, shape="plain", margin="0", **attrs)


def group(name, title, role, **extra):
    stroke, tint = ROLE[role]
    attrs = dict(label=f"<{pill(title, stroke)}>", labelloc="t", labeljust="c", style="dashed,rounded",
                 color=stroke, penwidth="1.6", bgcolor=tint, margin="22")
    attrs.update(extra)
    return Cluster(name, graph_attr=attrs)


def row(name):  # invisible cluster to keep its members on one rank (a grid row)
    return Cluster(name, graph_attr=dict(rank="same", style="invis", margin="4"))


REAL_EDGES = []  # count of drawn relations (from relations.yaml), excludes invisible spine edges


def flow(a, b, kind="sync", constraint=True, label=None, inferred=False):
    role, dashed, _ = EK[kind]
    color = EDGE_NAVY if kind == "network" else ROLE[role][0]
    style = "dashed" if dashed else "solid"
    if inferred:
        color, style = MUTED, "dotted"
    kw = dict(color=color, penwidth="1.4", style=style, arrowhead="normal", arrowsize="0.8",
              constraint="true" if constraint else "false")
    if label:
        kw["xlabel"] = f'<{txt(label, 8, color, bold=True)}>'
    a >> Edge(**kw) >> b
    REAL_EDGES.append(kind)


def header_html(logo, title, subtitle, width):
    sep = txt("     ", 11)
    terms = [
        ("──▶ inbound (sync)", ROLE["main"][0]),
        ("──▶ egress / network", EDGE_NAVY),
        ("──▶ data / write", ROLE["shared"][0]),
        ("╌╌▶ control (IAM)", ROLE["mgmt"][0]),
        ("╌╌▶ async / event", ROLE["hub"][0]),
        ("OPTIONAL = off in dev", ROLE["opt"][0]),
    ]
    legend = txt("Legend:  ", 11, INK, bold=True) + sep.join(txt(t, 11, c, bold=True) for t, c in terms)
    banner = (f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="14" BGCOLOR="{NAVY}" '
              f'STYLE="rounded" WIDTH="{width}">'
              f'<TR><TD WIDTH="60"><TABLE BORDER="0" CELLBORDER="0" BGCOLOR="white" STYLE="rounded" CELLPADDING="6">'
              f'<TR>{img_cell(logo, 46)}</TR></TABLE></TD>'
              f'<TD ALIGN="LEFT" BALIGN="LEFT" WIDTH="{width - 110}">{txt(title, 24, "white", BOLD)}<BR/>'
              f'{txt(subtitle, 12, "#D6E2F5")}</TD></TR></TABLE>')
    legend_row = (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="#D5DBE3" CELLPADDING="8" CELLSPACING="0" '
                  f'STYLE="rounded" BGCOLOR="white" WIDTH="{width}"><TR><TD ALIGN="LEFT">{legend}</TD></TR></TABLE>')
    return (f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="{width}">'
            f'<TR><TD>{banner}</TD></TR><TR><TD HEIGHT="6"></TD></TR>'
            f'<TR><TD>{legend_row}</TD></TR></TABLE>>')


HEADER = ("EKS dev — AWS Infrastructure",
          "layer 00-infra · VPC 10.0.0.0/16 · EKS eks-dev v1.36 · Karpenter · Pod-Identity add-ons · "
          "AMP/CloudWatch observability · ap-southeast-1")

OUT = os.path.splitext(os.path.basename(__file__))[0]


def build(header_width, outformat="png"):
    graph_attr = dict(
        rankdir="TB", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.4",
        nodesep="0.4", ranksep="0.9", fontname=FONT,
        label=header_html(icon(EKS), *HEADER, header_width), labelloc="t", labeljust="c",
        compound="true", outputorder="edgesfirst",
    )
    with Diagram("", filename=OUT, outformat=outformat, show=False, direction="TB", graph_attr=graph_attr,
                 node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0"),
                 edge_attr=dict(fontname=FONT)):

        # ── band 1 · edge ───────────────────────────────────────────────
        with group("edge", "Internet edge", "main"):
            users = node(card("Internet users", ["HTTPS clients"], "main", icon(Users), width=210))
            igw = node(card("Internet Gateway", ["eks-dev-igw"], "main", icon(InternetGateway), width=210))

        # ── band 2 · VPC (tiers stacked as rank=same rows) ──────────────
        with group("vpc", "VPC  eks-dev-vpc · 10.0.0.0/16 · 3 AZ (a/b/c)", "shared"):
            with row("vpc_pub"):  # public subnets · /20 · role/elb
                alb = node(card("Application LB", ["public · WAF-ready", "mgd by LB Controller"],
                                "main", icon(ElbApplicationLoadBalancer)))
                nat = node(card("NAT Gateway", ["1 shared + EIP", "egress for app tier"],
                                "mgmt", icon(NATGateway)))
            with row("vpc_app"):  # app subnets · /20 · nodes + pods
                ng = node(card("System node group", ["t4g.medium ARM64", "ON_DEMAND · 2–3"],
                               "main", icon(EC2Instance)))
                kp = node(card("Karpenter nodes", ["JIT provisioned", "spot + on-demand"],
                               "main", icon(EC2Instance)))
                vpce = node(card("VPC endpoints", ["S3 gw · ECR api/dkr", "Secrets Mgr · :443"],
                                 "shared", icon(Endpoint)))
            with row("vpc_iso"):  # isolated subnets · /24
                db = node(card("DB / cache tier", ["no internet route", "reserved (RDS/EC)"],
                               "mgmt", icon(PrivateSubnet)))

        # ── band 3 · EKS control plane + pod identity ───────────────────
        with group("cp", "EKS control plane (AWS-managed)", "hub"):
            with row("cp_row"):
                cp = node(card("EKS eks-dev", ["v1.36 · public+private", "coredns·kube-proxy·vpc-cni·ebs-csi"],
                               "hub", icon(EKS), width=270))
                podid = node(card("EKS Pod Identity", ["agent + associations", "IRSA for add-ons"],
                                  "hub", icon(IAMRole), width=270))

        # ── band 4 · AWS managed services (4-col grid) ──────────────────
        W_SVC = 200
        with group("svc", "AWS managed services (via Pod-Identity roles)", "shared"):
            with row("svc_r1"):
                ecr = node(card("ECR", ["images + helm"], "shared", icon(EC2ContainerRegistry), width=W_SVC))
                sm = node(card("Secrets Manager", ["ESO reads prod/*"], "shared", icon(SecretsManager), width=W_SVC))
                r53 = node(card("Route 53", ["external-dns", "cert-manager"], "shared", icon(Route53), width=W_SVC))
                acm = node(card("ACM / TLS", ["cert-manager"], "shared", icon(CertificateManager), width=W_SVC))
            with row("svc_r2"):
                sqs = node(card("SQS", ["spot interruption"], "shared", icon(SimpleQueueServiceSqs), width=W_SVC))
                eb = node(card("EventBridge", ["EC2 spot events"], "shared", icon(Eventbridge), width=W_SVC))
                cw = node(card("CloudWatch Logs", ["Fluent Bit · KEDA"], "shared", icon(Cloudwatch), width=W_SVC))
                amp = node(card("Managed Prometheus", ["ADOT+Prom write"], "shared", icon(AmazonManagedPrometheus), width=W_SVC))
            with row("svc_r3"):
                xray = node(card("X-Ray", ["ADOT traces"], "shared", icon(XRay), width=W_SVC))
                sns = node(card("SNS", ["AMP alerts"], "shared", icon(SimpleNotificationServiceSns), width=W_SVC))
                ce = node(card("Cost Explorer", ["Kubecost"], "shared", icon(CostExplorer), width=W_SVC))
                s3 = node(card("S3 tfstate", ["eks-iac-tfstate"], "shared", icon(S3), width=W_SVC))

        # ── band 5 · optional (OFF in dev) ──────────────────────────────
        with group("opt", "optional — OFF in dev (prod owns singletons)", "opt"):
            with row("opt_row"):
                waf = node(card("WAFv2", ["ALB regional ACL"], "opt", icon(WAF), tagged="OFF", width=210))
                bak = node(card("Velero backup", ["S3 + EBS snapshot"], "opt", icon(S3), tagged="OFF", width=210))
                sec = node(card("Security baseline", ["GuardDuty·Config", "CloudTrail·SecHub"], "opt",
                                icon(Cloudtrail), tagged="OFF", width=210))

        # ── relations (ids map to relations.yaml) ───────────────────────
        flow(users, igw, "sync", label="443")                 # r1
        flow(igw, alb, "network")                              # r2
        flow(alb, ng, "sync", constraint=False)               # r3
        flow(ng, nat, "network", constraint=False)             # r4
        flow(kp, nat, "network", constraint=False)
        flow(nat, igw, "network", constraint=False)            # r5
        flow(ng, vpce, "network", constraint=False)            # r6
        flow(vpce, ecr, "network", constraint=False)           # r7
        flow(vpce, sm, "network", constraint=False)            # r8
        flow(cp, ng, "control", label="443")                   # r9
        flow(cp, kp, "control", constraint=False)              # r10
        flow(ng, podid, "control", constraint=False)           # r11
        flow(eb, sqs, "async", constraint=False)               # r12
        flow(kp, sqs, "async", constraint=False)               # r13
        # pod-identity → services
        flow(podid, alb, "control", constraint=False, label="LBC")   # r14 (LBC manages ELB/ALB)
        flow(podid, r53, "control")                            # r15
        flow(podid, acm, "control", constraint=False)
        flow(podid, sm, "data", constraint=False)              # r16
        flow(podid, ecr, "data", constraint=False)             # r17
        flow(podid, cw, "data")                                # r18/r24
        flow(podid, sqs, "data", constraint=False)             # r19
        flow(podid, ce, "data", constraint=False)              # r20
        flow(podid, amp, "data", constraint=False)             # r22
        flow(podid, xray, "data", constraint=False)            # r23
        flow(amp, sns, "async", constraint=False)              # r25
        flow(cp, s3, "data", constraint=False, label="backend")  # r26

        # spine — one vertical chain forcing bands to stack top→bottom (weight high, invisible)
        for upper, lower in [(users, igw), (igw, alb), (alb, ng), (ng, db), (db, cp),
                             (cp, ecr), (ecr, sqs), (sqs, xray), (xray, waf)]:
            upper >> Edge(style="invis", weight="20") >> lower
        # left→right ordering within same-rank rows
        for seq in [(users, igw), (alb, nat), (ng, kp, vpce), (cp, podid),
                    (ecr, sm, r53, acm), (sqs, eb, cw, amp), (xray, sns, ce, s3),
                    (waf, bak, sec)]:
            for a, b in zip(seq, seq[1:]):
                a >> Edge(style="invis") >> b


def edge_check():
    """Layout the same graph to JSON and confirm every drawn edge has a routed position."""
    import json
    REAL_EDGES.clear()
    build(1200, outformat="dot")            # emits architecture.dot (graphviz source)
    df = Path(f"{OUT}.dot")
    if not df.exists():
        return None
    out = subprocess.run(["dot", "-Tjson"], input=df.read_text(), capture_output=True, text=True)
    df.unlink(missing_ok=True)
    if out.returncode != 0:
        return None
    data = json.loads(out.stdout)
    edges = data.get("edges", [])
    # a routed edge carries draw instructions (_draw_/_hdraw_) or an explicit pos
    routed = [e for e in edges if any("draw" in k for k in e) or "pos" in e]
    return len(edges), len(routed)


def render():
    from PIL import Image
    REAL_EDGES.clear()
    build(900)                               # pass 1 — measure content
    w1 = Image.open(f"{OUT}.png").width
    pad = 0.4
    hdr_pt = max(900, w1 - 2 * pad * 120) / 120 * 72
    REAL_EDGES.clear()
    build(hdr_pt)                            # pass 2 — header matches content width
    w2 = Image.open(f"{OUT}.png").width
    return w1, w2


if __name__ == "__main__":
    from PIL import Image
    chk = edge_check()                       # routing verification (temp json), runs first
    w1, w2 = render()                         # final two-pass png is the artifact
    final_w = Image.open(f"{OUT}.png").width
    print(f"pass1={w1}px  pass2={w2}px  final={final_w}px")
    print(f"relations drawn (visible edges) = {len(REAL_EDGES)}")
    print("width " + ("OK <=1920" if final_w <= 1920 else f"FAIL {final_w}>1920"))
    if chk:
        total, routed = chk
        print(f"graphviz edges total={total}  routed(has draw/pos)={routed}  "
              + ("OK all routed" if routed == total else "FAIL missing routes"))
