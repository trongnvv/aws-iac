"""EKS Deep-Dive — Reference Architecture (dev/lab size): architecture infographic.

Run:  uv run --with diagrams python architecture.py   → architecture.png
Content is data (cards / STEPS / BANNERS / CHECKS …); style lives in the helpers.
"""
import os
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EKS, EC2Instance, ECR
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import (
    ELB, InternetGateway, NATGateway, Route53, VPCElasticNetworkInterface,
)
from diagrams.aws.security import IAMRole, SecretsManager
from diagrams.aws.storage import S3

# ── style ────────────────────────────────────────────────────────────────────────────────────────
FONT, BOLD, MONO = "Noto Sans", "Noto Sans Bold", "DejaVu Sans Mono"
CANVAS, PANEL, NAVY, INK, MUTED = "#EEF1F5", "#FFFFFF", "#1F3A68", "#1B2433", "#5F6B7A"
ROLE = {  # one color per role: (stroke/pill, card tint)
    "main":   ("#2563EB", "#F3F7FF"),
    "hub":    ("#7C3AED", "#F7F3FF"),
    "shared": ("#16A34A", "#F2FBF5"),
    "opt":    ("#EA7A0C", "#FFF8F0"),
    "deny":   ("#DC2626", "#FFF3F3"),
    "mgmt":   ("#64748B", "#F6F7F9"),
}
W = 1880  # full-width rows (header, section 2, footer)
IW = W - 110  # content width inside the section-2 panel
_BASE = Path(diagrams.__file__).resolve().parent.parent


def icon(cls) -> str:
    return str(_BASE / cls._icon_dir / cls._icon)


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def txt(s, size=12, color=INK, face=FONT, bold=False):
    s = f"<B>{esc(s)}</B>" if bold else esc(s)
    return f'<FONT FACE="{face}" POINT-SIZE="{size}" COLOR="{color}">{s}</FONT>'


def img_cell(src, size=40, rowspan=1):
    return (f'<TD ROWSPAN="{rowspan}" FIXEDSIZE="TRUE" WIDTH="{size}" HEIGHT="{size}" VALIGN="MIDDLE">'
            f'<IMG SRC="{src}" SCALE="TRUE"/></TD>')


def badge_cell(letter, color, size=40, rowspan=1):
    return (f'<TD ROWSPAN="{rowspan}" FIXEDSIZE="TRUE" WIDTH="{size}" HEIGHT="{size}" BGCOLOR="{color}" '
            f'STYLE="rounded">{txt(letter, 18, "white", BOLD)}</TD>')


def pill(s, color, size=11):
    return (f'<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="3" CELLSPACING="0" STYLE="rounded" BGCOLOR="{color}">'
            f'<TR><TD>{txt(" " + s + " ", size, "white", BOLD)}</TD></TR></TABLE>')


def tag(s, color):  # small inline tag next to a card title
    return (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="{color}" CELLPADDING="1" CELLSPACING="0" STYLE="rounded">'
            f'<TR><TD>{txt(s, 8, color, BOLD)}</TD></TR></TABLE>')


def card(title, lines, role="main", ic=None, letter=None, tagged=None, width=300, rows=None):
    """White rounded card: icon left + bold title + muted fact lines (+ optional table rows)."""
    stroke, tint = ROLE[role]
    bg = tint if role in ("opt", "deny") else "white"
    n = 1 + len(lines)
    left = img_cell(ic, rowspan=n) if ic else badge_cell(letter or title[0].upper(), stroke, rowspan=n)
    head = txt(title, 13, INK, BOLD)
    if tagged:
        head = (f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0"><TR><TD>{head}</TD><TD WIDTH="6"></TD>'
                f'<TD>{tag(tagged, ROLE["opt"][0])}</TD></TR></TABLE>')
    body = "".join(f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">{txt(l, 10, MUTED)}</TD></TR>' for l in lines)
    extra = ""
    if rows:  # route-table rows: (cidr, target, role)
        extra = "".join(
            f'<TR><TD COLSPAN="2" BGCOLOR="{ROLE[r][1]}" CELLPADDING="3">'
            f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="{width - 24}"><TR>'
            f'<TD ALIGN="LEFT">{txt(c, 10, ROLE[r][0] if r != "hub" else INK, MONO)}</TD>'
            f'<TD ALIGN="RIGHT">{txt(t, 9, ROLE[r][0] if r != "hub" else MUTED)}</TD></TR></TABLE></TD></TR>'
            for c, t, r in rows)
    return (f'<<TABLE BORDER="1" CELLBORDER="0" COLOR="{stroke if role in ("opt", "deny") else "#D5DBE3"}" STYLE="rounded" '
            f'BGCOLOR="{bg}" CELLPADDING="4" CELLSPACING="2" WIDTH="{width}">'
            f'<TR>{left}<TD ALIGN="LEFT" WIDTH="{width - 60}">{head}</TD></TR>{body}{extra}</TABLE>>')


def node(label_html, **attrs):
    return Node(label_html, shape="plain", margin="0", **attrs)


def group(title, role, **extra):
    stroke, tint = ROLE[role]
    attrs = dict(label=f"<{pill(title, stroke)}>", labelloc="t", labeljust="c", style="dashed,rounded",
                 color=stroke, penwidth="1.6", bgcolor=tint, margin="16", rank="same")
    attrs.update(extra)
    return box(title, attrs)


def box(name, attrs):  # cluster name must be unique; the visible label comes from graph_attr
    return Cluster(name, graph_attr=attrs)


def section_label(num, title, width=None):
    w = f' WIDTH="{width}"' if width else ""
    pad = f' WIDTH="{width - 400}"' if width else ""
    return (f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="2"{w}><TR>'
            f'<TD FIXEDSIZE="TRUE" WIDTH="30" HEIGHT="30" BGCOLOR="{NAVY}" STYLE="rounded">'
            f'{txt(str(num), 15, "white", BOLD)}</TD>'
            f'<TD WIDTH="10"></TD><TD ALIGN="LEFT">{txt(title, 20, INK, BOLD)}</TD>'
            f'<TD{pad}></TD></TR></TABLE>>')


def flow(a, b, role, dashed=False, constraint=True):
    a >> Edge(color=ROLE[role][0], penwidth="2.0", style="dashed" if dashed else "solid",
              arrowsize="0.8", constraint="true" if constraint else "false") >> b


def header_html(logo, title, subtitle):
    return (f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="14" BGCOLOR="{NAVY}" STYLE="rounded" WIDTH="{W}">'
            f'<TR><TD WIDTH="64"><TABLE BORDER="0" CELLBORDER="0" BGCOLOR="white" STYLE="rounded" CELLPADDING="6">'
            f'<TR>{img_cell(logo, 52)}</TR></TABLE></TD>'
            f'<TD ALIGN="LEFT" BALIGN="LEFT" WIDTH="{W - 120}">{txt(title, 26, "white", BOLD)}<BR/>'
            f'{txt(subtitle, 13, "#D6E2F5")}</TD></TR></TABLE>>')


def steps_row(steps):
    cells = []
    for i, (name, folder, builds, role) in enumerate(steps, 1):
        c = ROLE[role][0] if role == "opt" else NAVY
        cells.append(
            f'<TD BGCOLOR="{c}" STYLE="rounded" CELLPADDING="10" WIDTH="{IW // len(steps) - 40}" ALIGN="LEFT" BALIGN="LEFT">'
            f'{txt(f"{i}  {name}", 16, "white", BOLD)}  {txt(folder, 10, "#D6E2F5", MONO)}<BR/>'
            f'{txt(builds, 10, "white")}</TD>')
        if i < len(steps):
            cells.append(f'<TD>{txt("▶", 14, MUTED)}</TD>')
    return f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="4" CELLPADDING="0"><TR>{"".join(cells)}</TR></TABLE>'


def rules_banner(title, rules, role=None):
    ink, bg = (ROLE[role][0], ROLE[role][1]) if role else (NAVY, "#E3EAF5")
    body = f'  {txt("•", 12, MUTED)}  '.join(txt(r, 11) for r in rules)
    return (f'<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="10" CELLSPACING="0" STYLE="rounded" BGCOLOR="{bg}" WIDTH="{IW}">'
            f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">{txt(title, 12, ink, BOLD)}  {body}</TD></TR></TABLE>')


def checks_row(title, ic, checks, per=3):
    rows = []
    for k in range(0, len(checks), per):
        chunk = checks[k:k + per]
        tds = []
        for cid, what, expect, role in chunk:
            stroke, tint = ROLE[role]
            mark = {"shared": "✔", "deny": "✘", "opt": "→", "mgmt": "✔"}[role]
            tds.append(
                f'<TD BGCOLOR="{tint}" COLOR="{stroke}" BORDER="1" STYLE="rounded" CELLPADDING="7" '
                f'ALIGN="LEFT" BALIGN="LEFT" WIDTH="{(IW - 260) // per}">'
                f'{txt(cid, 11, stroke, BOLD)}  {txt(what, 11, INK, MONO)}<BR/>'
                f'{txt(mark + " " + expect, 11, stroke, BOLD)}</TD>')
        tds += [f'<TD WIDTH="{(IW - 260) // per}"></TD>'] * (per - len(chunk))
        rows.append("".join(tds))
    n = len(rows)
    first = (f'{img_cell(ic, 40, rowspan=n)}'
             f'<TD ROWSPAN="{n}" ALIGN="LEFT" BALIGN="LEFT" WIDTH="150">{txt(title[0], 15, INK, BOLD)}<BR/>'
             f'{txt(title[1], 11, MUTED)}</TD>')
    trs = "".join(f"<TR>{first if i == 0 else ''}{r}</TR>" for i, r in enumerate(rows))
    return (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="{ROLE["shared"][0]}" STYLE="dashed,rounded" CELLSPACING="6" '
            f'CELLPADDING="2" BGCOLOR="white" WIDTH="{IW}">{trs}</TABLE>')


def footer(title, items):
    body = f'   {txt("•", 12, MUTED)}   '.join(txt(i, 11, INK) for i in items)
    return (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="#D5DBE3" STYLE="rounded" CELLPADDING="12" CELLSPACING="0" BGCOLOR="white" WIDTH="{W}">'
            f'<TR><TD ALIGN="LEFT" WIDTH="200">{txt("$ " + title, 17, ROLE["shared"][0], BOLD)}</TD>'
            f'<TD ALIGN="LEFT" BALIGN="LEFT" WIDTH="{W - 320}">{body}</TD></TR></TABLE>')


def section2_html(steps, banners, checks):
    return (f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="{W}">'
            f'<TR><TD HEIGHT="18"></TD></TR>'
            f'<TR><TD><TABLE BORDER="1" CELLBORDER="0" COLOR="#D5DBE3" STYLE="rounded" BGCOLOR="{PANEL}" CELLPADDING="10" '
            f'CELLSPACING="6" WIDTH="{W - 55}">'
            f'<TR><TD ALIGN="LEFT">{section_label(2, "Layered deploy & verification", IW)[1:-1]}</TD></TR>'
            f'<TR><TD ALIGN="LEFT">{steps_row(steps)}</TD></TR>'
            + "".join(f'<TR><TD ALIGN="LEFT">{rules_banner(*b)}</TD></TR>' for b in banners) +
            f'<TR><TD ALIGN="LEFT">{checks_row(*checks)}</TD></TR>'
            f'</TABLE></TD></TR>'
            f'<TR><TD HEIGHT="14"></TD></TR>'
            f'<TR><TD>{footer(*FOOTER)}</TD></TR></TABLE>>')


# ── content (from envs/dev *.tf, 01-addons/02-platform helmfile and docs/ARCHITECTURE.md) ──────
HEADER = ("AWS EKS Deep-Dive — Reference Architecture (dev/lab size)",
          "Kubernetes 1.36 on EKS · 3-AZ VPC (public / private-app / private-isolated subnets) · "
          "AWS-managed control plane · ALB north-south · Karpenter nodes · GitOps via Argo CD · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("Infra", "00-infra/", "network · EKS 1.36 · karpenter-infra · addon-IAM · security-baseline · obs-aws · backup · WAF", "main"),
    ("Add-ons", "01-addons/", "karpenter · storageclass · metrics-server · LBC · external-dns · cert-manager · external-secrets", "main"),
    ("Platform", "02-platform/", "argocd · kube-prometheus observability · observability-aws (ADOT→AMP)", "main"),
    ("Application", "03-application/", "grpc-debug · synced by Argo CD", "opt"),
]
BANNERS = [
    ("Invariants:", [
        "control plane AWS-managed, outside the VPC",
        "only EKS ENIs + API endpoint touch subnets",
        "3 tiers: public = ALB/NAT · private-app = nodes/pods + karpenter tag · private-isolated = no internet route",
        "ECR / Secrets via VPC interface endpoints — skip NAT",
        "WAF = web ACL attached to ALB",
        "no SSH — SSM / IRSA / Pod Identity",
    ]),
    ("Not provisioned (add at edge if needed):", [
        "CloudFront (CDN)",
        "Shield Advanced (DDoS)",
        "egress Network Firewall + per-AZ NAT are large-size only",
    ], "opt"),
]
CHECKS = (("Deploy & verify", "./deploy.sh <layer>"), icon(EKS), [
    ("D0", "./deploy.sh 00-infra", "VPC + EKS 1.36 up", "shared"),
    ("D1", "kubectl get nodes", "Karpenter provisions on demand", "shared"),
    ("D2", "kubectl get ingress", "ALB provisioned via LBC", "shared"),
    ("D3", "argocd app list", "03-application synced by Argo CD", "mgmt"),
    ("D4", "obs: AMP + Grafana", "kube-prometheus · ADOT → AMP", "shared"),
    ("D5", "external-secrets", "pulls from Secrets Manager (IRSA)", "mgmt"),
])
FOOTER = ("Cost & teardown", [
    "dev preset = small: single NAT · public API · nothing paid beyond base",
    "./teardown.sh — reverse order, guards skip unapplied layers",
    "auto-sweeps orphaned LBs / ENIs / SGs / EIPs before destroying the VPC",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="0.9", fontname=FONT, label=header_html(icon(EKS), *HEADER), labelloc="t",
    labeljust="c", compound="true", outputorder="edgesfirst",
)

with Diagram("", filename=OUT, outformat="png", show=False, direction="LR", graph_attr=graph_attr,
             node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0", style="", labelloc="c"),
             edge_attr=dict(fontname=FONT)):
    # invisible wrapper: its bottom label carries every full-width row (section 2 + footer)
    with box("wrapper", dict(label=section2_html(STEPS, BANNERS, CHECKS), labelloc="b",
                             labeljust="c", pencolor="transparent", bgcolor="transparent", margin="0")):
        with box("section1", dict(label=section_label(1, "Topology & traffic flow", W - 16),
                                  labelloc="t", labeljust="l", style="rounded", color="#D5DBE3",
                                  bgcolor=PANEL, margin="22")):
            # column 1 — internet
            with group("Internet · external", "opt"):
                inet = node(card("Internet", ["clients / public", "reaches the ALB over HTTPS"], "opt",
                                 letter="🌐", width=250))

            # column 2 — public subnets (edge)
            with group("public subnets · tag role/elb · 3 AZ", "opt"):
                alb = node(card("ALB", ["L7 · provisioned by LBC", "from Ingress (class alb) / Gateway API",
                                        "WAF web ACL attached"], "opt", icon(ELB), width=300))
                nat = node(card("NAT ×1", ["single NAT (dev size)", "egress for private-app subnets"],
                                "main", icon(NATGateway), width=300))
                igw = node(card("Internet Gateway", ["VPC edge to the internet"], "main",
                                icon(InternetGateway), width=300))

            # column 3 — private-app subnets (nodes + add-on / platform stack)
            with group("private-app subnets · internal-elb + karpenter.sh/discovery · 3 AZ", "shared"):
                nodes = node(card("EKS nodes / pods", ["Karpenter-provisioned EC2 · on-demand",
                                                       "pods on secondary-CIDR subnets",
                                                       "IRSA / Pod Identity, no SSH"], "shared",
                                  icon(EC2Instance), width=320))
                addons = node(card("add-ons (01-addons)", ["karpenter · metrics-server · LBC",
                                                           "cert-manager · external-secrets · storageclass"],
                                   "main", letter="A", width=320))
                platform = node(card("platform (02-platform)", ["argocd (GitOps app-of-apps)",
                                                                "kube-prometheus · observability-aws (ADOT)"],
                                     "main", letter="P", width=320))
                app = node(card("application (03-application)", ["grpc-debug", "synced by Argo CD"], "opt",
                                letter="G", width=320, tagged="GITOPS"))

            # column 4 — private-isolated subnets (reserved, no internet)
            with group("private-isolated subnets · NO internet route · 3 AZ", "mgmt"):
                iso = node(card("reserved data tier", ["RDS · ElastiCache", "separate stack — not in dev",
                                                       "no route to NAT / IGW"], "mgmt",
                                letter="D", width=280))

            # column 5 — AWS managed (outside the VPC)
            with group("AWS managed · outside your VPC", "hub"):
                cpane = node(card("EKS control plane", ["AWS-managed · outside the VPC",
                                                        "public API endpoint (dev)",
                                                        "cross-account ENIs + API touch subnets"], "hub",
                                  icon(EKS), width=320))
                ecr = node(card("ECR + Secrets Manager", ["image pulls + secret reads",
                                                          "via VPC interface endpoints (skip NAT)"], "hub",
                                icon(ECR), width=320))
                amp = node(card("AMP / CloudWatch", ["Managed Prometheus · metrics",
                                                     "CloudWatch Logs (Fluent Bit)"], "hub",
                                icon(Cloudwatch), width=320))

            # column 6 — foundation (shared, run once)
            with group("foundation · shared (run once)", "main"):
                found = node(card("foundation", ["S3 tfstate + lock",
                                                 "Route 53 zone · ACM cert"], "main", icon(S3), width=270))
                dns = node(card("Route 53 + ACM", ["DNS records (external-dns)",
                                                   "TLS cert for the ALB"], "main", icon(Route53), width=270))

            # main north-south path: Internet → ALB → nodes
            flow(inet, alb, "opt")
            flow(alb, nodes, "shared")
            # egress: nodes → NAT → IGW → Internet
            flow(nodes, nat, "main")
            flow(nat, igw, "main")
            flow(igw, inet, "main", constraint=False)
            # nodes → ECR / Secrets via interface endpoints
            flow(nodes, ecr, "hub", dashed=True)
            # control plane cross-account ENIs ⋯ nodes
            flow(cpane, nodes, "hub", dashed=True, constraint=False)
            # foundation wires DNS / TLS to the ALB
            flow(dns, alb, "main", dashed=True, constraint=False)

            nodes >> Edge(style="invis") >> iso  # keep private-isolated between app and managed
            # column ordering only: within a rank=same column (LR) a flat edge a → b puts b ABOVE a,
            # so each list below is written top → bottom and wired in reverse.
            for col in [[inet], [alb, nat, igw], [nodes, addons, platform, app], [iso],
                        [cpane, ecr, amp], [found, dns]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
