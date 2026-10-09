"""EKS env=dev — VPC / network deep-dive (ap-southeast-1).

Drawn only from relations.yaml (built from eks/modules/network/*.tf).
Run:  uv run --with diagrams --with pillow --with pyyaml python architecture.py  → architecture.png
Content is data (CARDS/EDGES); style lives in the helpers. AZ × tier subnet grid + routing.
"""
import os
import subprocess
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.general import InternetAlt1
from diagrams.aws.network import (
    Endpoint, InternetGateway, NATGateway, NetworkFirewall, Privatelink, PrivateSubnet,
    PublicSubnet, RouteTable,
)

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
EK = {  # edge kind → (role color key, dashed)
    "network": ("navy",   False),
    "data":    ("shared", False),
    "deny":    ("deny",   True),
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


def badge_cell(letter, color, size=38, rowspan=1):
    return (f'<TD ROWSPAN="{rowspan}" FIXEDSIZE="TRUE" WIDTH="{size}" HEIGHT="{size}" BGCOLOR="{color}" '
            f'STYLE="rounded" VALIGN="MIDDLE">{txt(letter, 15, "white", BOLD)}</TD>')


def pill(s, color, size=11):
    return (f'<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="4" CELLSPACING="0" STYLE="rounded" BGCOLOR="{color}">'
            f'<TR><TD>{txt(" " + s + " ", size, "white", BOLD)}</TD></TR></TABLE>')


def tag(s, color):
    return (f'<TABLE BORDER="1" CELLBORDER="0" COLOR="{color}" CELLPADDING="1" CELLSPACING="0" STYLE="rounded">'
            f'<TR><TD>{txt(s, 8, color, BOLD)}</TD></TR></TABLE>')


def card(title, lines, role="main", ic=None, letter=None, tagged=None, width=250, rows=None):
    """White rounded card: icon/badge left + bold title + muted fact lines (+ optional route rows)."""
    stroke, _ = ROLE[role]
    n = 1 + len(lines) + (len(rows) if rows else 0)
    left = badge_cell(letter, stroke, rowspan=n) if letter else (img_cell(ic, rowspan=n) if ic else "")
    head = txt(title, 12, INK, BOLD)
    if tagged:
        head = (f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0"><TR><TD>{head}</TD>'
                f'<TD WIDTH="6"></TD><TD>{tag(tagged, ROLE["opt"][0])}</TD></TR></TABLE>')
    body = "".join(f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">{txt(l, 9, MUTED)}</TD></TR>' for l in lines)
    extra = ""
    if rows:  # route rows: (cidr, target, role)
        extra = "".join(
            f'<TR><TD BGCOLOR="{ROLE[r][1]}" CELLPADDING="3">'
            f'<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="{width - 20}"><TR>'
            f'<TD ALIGN="LEFT">{txt(c, 9, ROLE[r][0], MONO)}</TD>'
            f'<TD ALIGN="RIGHT">{txt(t, 8, ROLE[r][0])}</TD></TR></TABLE></TD></TR>'
            for c, t, r in rows)
    border = stroke if role in ("opt", "deny", "hub", "shared") else "#D5DBE3"
    return (f'<<TABLE BORDER="1" CELLBORDER="0" COLOR="{border}" STYLE="rounded" BGCOLOR="white" '
            f'CELLPADDING="6" CELLSPACING="2" WIDTH="{width}">'
            f'<TR>{left}<TD ALIGN="LEFT" WIDTH="{width - 54}">{head}</TD></TR>{body}{extra}</TABLE>>')


def node(label_html, **attrs):
    return Node(label_html, shape="plain", margin="0", **attrs)


def group(name, title, role, **extra):
    stroke, tint = ROLE[role]
    attrs = dict(label=f"<{pill(title, stroke)}>", labelloc="t", labeljust="c", style="dashed,rounded",
                 color=stroke, penwidth="1.6", bgcolor=tint, margin="22")
    attrs.update(extra)
    return Cluster(name, graph_attr=attrs)


def row(name):  # invisible cluster → members share one rank (a grid row)
    return Cluster(name, graph_attr=dict(rank="same", style="invis", margin="4"))


REAL_EDGES = []


def flow(a, b, kind="network", constraint=False, label=None, inferred=False):
    rolekey, dashed = EK[kind]
    color = EDGE_NAVY if rolekey == "navy" else ROLE[rolekey][0]
    style = "dashed" if dashed else "solid"
    if inferred:
        color, style = MUTED, "dotted"
    kw = dict(color=color, penwidth="1.4", style=style, arrowhead="normal", arrowsize="0.8",
              constraint="true" if constraint else "false")
    if kind == "deny":
        kw.update(dir="both")
    if label:
        kw["xlabel"] = f'<{txt(label, 8, color, bold=True)}>'
    a >> Edge(**kw) >> b
    REAL_EDGES.append(kind)


def header_html(logo, title, subtitle, width):
    sep = txt("     ", 11)
    terms = [("──▶ route / association", EDGE_NAVY), ("──▶ data (443)", ROLE["shared"][0]),
             ("╌╌ no route (isolated)", ROLE["deny"][0]), ("OFF = disabled in dev", ROLE["opt"][0])]
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


HEADER = ("EKS dev — VPC & Network topology",
          "VPC 10.0.0.0/16 · 3 AZ (a/b/c) · public/app/isolated tiers · 1 shared NAT · "
          "route tables · S3 + interface endpoints · ap-southeast-1")

OUT = os.path.splitext(os.path.basename(__file__))[0]


def build(header_width, outformat="png"):
    graph_attr = dict(
        rankdir="TB", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.4",
        nodesep="0.4", ranksep="0.95", fontname=FONT,
        label=header_html(icon(InternetAlt1), *HEADER, header_width), labelloc="t", labeljust="c",
        compound="true", outputorder="edgesfirst",
    )
    with Diagram("", filename=OUT, outformat=outformat, show=False, direction="TB", graph_attr=graph_attr,
                 node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0"),
                 edge_attr=dict(fontname=FONT)):

        # ── band 1 · VPC subnet grid (tier rows × AZ columns) ───────────
        with group("vpc", "VPC  eks-dev-vpc · 10.0.0.0/16 · DNS on", "shared"):
            with row("r_pub"):  # public tier — ALB + NAT live here, role/elb
                pub_a = node(card("public-1a", ["10.0.0.0/20", "role/elb · hosts NAT"], "main", icon(PublicSubnet)))
                pub_b = node(card("public-1b", ["10.0.16.0/20", "role/elb · map-public-ip"], "main", icon(PublicSubnet)))
                pub_c = node(card("public-1c", ["10.0.32.0/20", "role/elb"], "main", icon(PublicSubnet)))
            with row("r_app"):  # app tier — EKS nodes/pods
                app_a = node(card("app-1a", ["10.0.48.0/20", "internal-elb · karpenter"], "main", icon(PrivateSubnet)))
                app_b = node(card("app-1b", ["10.0.64.0/20", "internal-elb · karpenter"], "main", icon(PrivateSubnet)))
                app_c = node(card("app-1c", ["10.0.80.0/20", "internal-elb · karpenter"], "main", icon(PrivateSubnet)))
            with row("r_iso"):  # isolated tier — DB/cache, no internet
                iso_a = node(card("isolated-1a", ["10.0.96.0/24", "no route"], "mgmt", icon(PrivateSubnet)))
                iso_b = node(card("isolated-1b", ["10.0.97.0/24", "no route"], "mgmt", icon(PrivateSubnet)))
                iso_c = node(card("isolated-1c", ["10.0.98.0/24", "no route"], "mgmt", icon(PrivateSubnet)))

        # ── band 2 · route tables ───────────────────────────────────────
        with group("rtg", "Route tables", "hub"):
            with row("r_rt"):
                pub_rt = node(card("public-rt", ["assoc: 3 public"], "main", letter="RT", width=220,
                                   rows=[("0.0.0.0/0", "IGW", "main")]))
                art_a = node(card("app-rt-1a", ["assoc: app-1a"], "shared", letter="RT", width=220,
                                  rows=[("0.0.0.0/0", "NAT", "shared"), ("S3 pl", "s3-gw", "hub")]))
                art_b = node(card("app-rt-1b", ["assoc: app-1b"], "shared", letter="RT", width=220,
                                  rows=[("0.0.0.0/0", "NAT", "shared"), ("S3 pl", "s3-gw", "hub")]))
                art_c = node(card("app-rt-1c", ["assoc: app-1c"], "shared", letter="RT", width=220,
                                  rows=[("0.0.0.0/0", "NAT", "shared"), ("S3 pl", "s3-gw", "hub")]))
            with row("r_rt2"):
                iso_rt = node(card("isolated-rt", ["assoc: 3 isolated"], "mgmt", letter="RT", width=220,
                                   rows=[("local only", "no 0/0", "deny"), ("S3 pl", "s3-gw", "hub")]))

        # ── band 3 · VPC endpoints ──────────────────────────────────────
        with group("endp", "VPC endpoints (skip NAT)", "shared"):
            with row("r_e"):
                s3_gw = node(card("S3 gateway endpoint", ["free · prefix-list", "to app-rt×3 + iso-rt"],
                                  "shared", icon(Endpoint), width=240))
                ifce = node(card("interface endpoints", ["ecr.api · ecr.dkr", "secretsmanager · in app"],
                                 "shared", icon(Privatelink), width=240))
                vpce_sg = node(card("vpce-sg", ["ingress 443", "from 10.0.0.0/16"], "mgmt",
                                    letter="SG", width=200))

        # ── band 4 · edge gateways ──────────────────────────────────────
        with group("gw", "Edge gateways", "main"):
            with row("r_g"):
                nat = node(card("NAT Gateway", ["1 shared + EIP", "in public-1a"], "main", icon(NATGateway), width=230))
                igw = node(card("Internet Gateway", ["eks-dev-igw"], "main", icon(InternetGateway), width=230))

        # ── band 5 · internet ───────────────────────────────────────────
        with group("inet", "Internet", "opt"):
            internet = node(card("Internet", ["0.0.0.0/0"], "opt", icon(InternetAlt1), width=220))

        # ── band 6 · optional (OFF in dev) ──────────────────────────────
        with group("opt", "optional — OFF in dev", "opt"):
            with row("r_opt"):
                pod_sn = node(card("pod subnets", ["100.64.0.0/16", "CNI custom net"], "opt",
                                   icon(PrivateSubnet), tagged="OFF", width=230))
                nfw = node(card("Network Firewall", ["centralized egress", "app→fw→NAT"], "opt",
                                icon(NetworkFirewall), tagged="OFF", width=230))

        # ── relations (ids map to relations.yaml) ───────────────────────
        # public tier → public-rt → IGW
        flow(pub_a, pub_rt); flow(pub_b, pub_rt); flow(pub_c, pub_rt)      # n3-n5
        flow(pub_rt, igw, label="0/0")                                      # n6
        # app tier → per-AZ app-rt → shared NAT
        flow(app_a, art_a); flow(app_b, art_b); flow(app_c, art_c)         # n7-n9
        flow(art_a, nat); flow(art_b, nat); flow(art_c, nat)               # n10-n12
        # isolated tier → isolated-rt (no internet)
        flow(iso_a, iso_rt); flow(iso_b, iso_rt); flow(iso_c, iso_rt)      # n13-n15
        flow(iso_rt, igw, kind="deny", label="no 0/0")                     # n16
        # NAT → IGW → Internet
        flow(nat, igw, label="egress")                                     # n2
        flow(igw, internet)                                                # n1
        # S3 gateway endpoint → route tables
        flow(s3_gw, art_a); flow(s3_gw, art_b); flow(s3_gw, art_c); flow(s3_gw, iso_rt)  # n17-n20
        # interface endpoints: reached from app tier; SG guards 443
        flow(app_b, ifce, kind="data", label="443")                        # n21
        flow(vpce_sg, ifce, label="443")                                   # n22

        # ── spine (invisible, stacks bands & orders rows) ───────────────
        for u, l in [(pub_b, app_b), (app_b, iso_b), (iso_b, art_b), (art_b, iso_rt),
                     (iso_rt, ifce), (ifce, nat), (nat, internet), (internet, pod_sn)]:
            u >> Edge(style="invis", weight="20") >> l
        for seq in [(pub_a, pub_b, pub_c), (app_a, app_b, app_c), (iso_a, iso_b, iso_c),
                    (pub_rt, art_a, art_b, art_c), (s3_gw, ifce, vpce_sg),
                    (nat, igw), (pod_sn, nfw)]:
            for a, b in zip(seq, seq[1:]):
                a >> Edge(style="invis") >> b


def edge_check():
    """Layout the same graph to JSON and confirm every drawn edge is routed."""
    import json
    REAL_EDGES.clear()
    build(1200, outformat="dot")
    df = Path(f"{OUT}.dot")
    if not df.exists():
        return None
    out = subprocess.run(["dot", "-Tjson"], input=df.read_text(), capture_output=True, text=True)
    df.unlink(missing_ok=True)
    if out.returncode != 0:
        return None
    data = json.loads(out.stdout)
    edges = data.get("edges", [])
    routed = [e for e in edges if any("draw" in k for k in e) or "pos" in e]
    return len(edges), len(routed)


def render():
    from PIL import Image
    REAL_EDGES.clear()
    build(900)
    w1 = Image.open(f"{OUT}.png").width
    pad = 0.4
    hdr_pt = max(900, w1 - 2 * pad * 120) / 120 * 72
    REAL_EDGES.clear()
    build(hdr_pt)
    w2 = Image.open(f"{OUT}.png").width
    return w1, w2


if __name__ == "__main__":
    from PIL import Image
    chk = edge_check()
    w1, w2 = render()
    final_w = Image.open(f"{OUT}.png").width
    print(f"pass1={w1}px  pass2={w2}px  final={final_w}px")
    print(f"relations drawn (visible edges) = {len(REAL_EDGES)}")
    print("width " + ("OK <=1920" if final_w <= 1920 else f"FAIL {final_w}>1920"))
    if chk:
        total, routed = chk
        print(f"graphviz edges total={total}  routed={routed}  "
              + ("OK all routed" if routed == total else "FAIL missing routes"))
