"""Lab 3 — PrivateLink (share one service across VPCs, overlapping CIDR): architecture infographic.

Run:  uv run --with diagrams python architecture.py   → architecture.png
Content is data (cards / STEPS / BANNERS / CHECKS …); style lives in the helpers.
"""
import os
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EC2Instance
from diagrams.aws.management import SystemsManager
from diagrams.aws.network import (
    ElbNetworkLoadBalancer, Endpoint, Privatelink, RouteTable, VPCElasticNetworkInterface,
)
from diagrams.aws.security import IAMRole

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


# ── content (AWS resources as they appear in the console, not Terraform names) ───────────────────
HEADER = ("AWS Network Lab 3 — PrivateLink (share one service across overlapping CIDRs)",
          "Endpoint Service (NLB-backed) in the provider VPC ⇄ Interface VPC Endpoint (ENI) in the consumer "
          "VPC · reaches the service though BOTH VPCs are 10.0.0.0/16 — no route ever consulted · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("VPC", "1-vpc/", "provider + consumer VPC (identical 10.0.0.0/16) · Subnet · Internet Gateway · Security Group", "main"),
    ("Provider", "2-provider/", "EC2 instance · Network Load Balancer · Endpoint Service (NLB-backed) · IAM role", "main"),
    ("Consumer", "3-consumer/", "Interface VPC Endpoint (ENI) + endpoint Security Group", "main"),
    ("EC2", "4-ec2/", "consumer EC2 instance · curls the endpoint DNS name", "main"),
]
BANNERS = [
    ("Invariants:", [
        "overlapping CIDR on purpose — both VPCs are 10.0.0.0/16",
        "no VPC Peering / Transit Gateway — the endpoint is the only path",
        "private DNS disabled — curl the vpce-… endpoint DNS name",
        "acceptance not required — no approval handshake",
        "Endpoint Security Group: ingress 80/443 from 10.0.0.0/16",
        "consumer host: egress only · no SSH — SSM only",
    ]),
    ("⚠ Built blind — verify live:", [
        "Endpoint Service reaches Available",
        "Interface VPC Endpoint reaches available (not pendingAcceptance)",
        "NLB target healthy",
        "curl reaches the service across the overlapping 10.0.0.0/16",
    ], "deny"),
]
CHECKS = (("Verify", "via SSM Session Manager + AWS CLI"), icon(SystemsManager), [
    ("T0", "describe-instance-information", "consumer host Online", "mgmt"),
    ("T1", "describe-vpc-endpoint-service-configurations", "Endpoint Service Available · accept=false", "shared"),
    ("T2", "describe-vpc-endpoints State", "Interface VPC Endpoint available", "shared"),
    ("T3", "curl http://$EP_DNS (across the overlap)", "✓ proof page from the provider VPC", "shared"),
    ("T4a", "describe-vpc-peering-connections", "✘ empty (no Peering / Transit Gateway)", "deny"),
    ("T4b", "curl http://$SVC_IP (direct private IP)", "✘ no route · endpoint still works", "deny"),
])
FOOTER = ("Cost & teardown", [
    "Network Load Balancer (internal) ≈ $0.0225/h + LCU",
    "Interface VPC Endpoint ≈ $0.01/AZ-h (1 AZ) + data",
    "2× EC2 t4g.micro ≈ $0.017/h",
    "2× public IPv4 ≈ $0.01/h",
    "≈ $0.06/h → ./teardown.sh when done",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="0.9", fontname=FONT, label=header_html(icon(Privatelink), *HEADER), labelloc="t",
    labeljust="c", compound="true", outputorder="edgesfirst",
)

with Diagram("", filename=OUT, outformat="png", show=False, direction="LR", graph_attr=graph_attr,
             node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0", style="", labelloc="c"),
             edge_attr=dict(fontname=FONT)):
    # invisible wrapper: its bottom label carries every full-width row (section 2 + footer)
    with box("wrapper", dict(label=section2_html(STEPS, BANNERS, CHECKS), labelloc="b",
                             labeljust="c", pencolor="transparent", bgcolor="transparent", margin="0")):
        with box("section1", dict(label=section_label(1, "AWS resources created & how traffic reaches the service", W - 16),
                                  labelloc="t", labeljust="l", style="rounded", color="#D5DBE3",
                                  bgcolor=PANEL, margin="22")):
            # column 1 — consumer VPC B (AWS objects; title matches content)
            with group("Consumer VPC · 10.0.0.0/16", "main"):
                client = node(card("EC2 instance · Subnet · SG (consumer)", [
                    "Subnet 10.0.0.0/24 (public) · t4g.micro",
                    "Security Group: egress only (the host just curls out)",
                    "no SSH · reaches the service via the endpoint DNS",
                ], "main", icon(EC2Instance), width=340))
                eni = node(card("Interface VPC Endpoint (ENI)", [
                    "ENI with a private IP in the consumer Subnet",
                    "terminates the consumer's TCP (not a route)",
                    "Security Group: ingress 80/443 from 10.0.0.0/16",
                    "private DNS disabled · resolves the vpce-… name",
                ], "main", icon(VPCElasticNetworkInterface), width=340))
                b_rt = node(card("Route table (consumer)", [], "main", icon(RouteTable), width=340,
                                 rows=[("0.0.0.0/0", "→ Internet Gateway (SSM only)", "main"),
                                       ("10.0.0.0/16", "→ local (own VPC) — NO route to provider", "deny")]))

            # column 2 — overlapping CIDR (hero) + PrivateLink endpoint service
            with group("PrivateLink · endpoint DNS, not L3", "shared"):
                overlap = node(card("Overlapping CIDR 10.0.0.0/16", [
                    "BOTH VPCs use the SAME block — on purpose",
                    "consumer talks only to the ENI (a private IP in ITS VPC)",
                    "no route between the two 10.0.0.0/16 is ever consulted",
                    "the overlap is irrelevant — what Peering / TGW can't do",
                ], "deny", letter="★", width=360))
                pl = node(card("Endpoint Service (NLB-backed)", [
                    "com.amazonaws.vpce.<region>.vpce-svc-xxxx",
                    "acceptance not required (accept=false)",
                    "no VPC Peering / Transit Gateway — the only path in",
                ], "shared", icon(Endpoint), width=360))

            # column 3 — provider VPC A
            with group("Provider VPC · 10.0.0.0/16 (overlaps!)", "hub"):
                nlb = node(card("Network Load Balancer (internal) :80", [
                    "internal NLB · the only thing an Endpoint Service can front",
                    "Target group net-lab-pl-tg · TCP :80 · health TCP 80",
                ], "hub", icon(ElbNetworkLoadBalancer), width=360))
                svc = node(card("EC2 instance · Subnet · SG (service)", [
                    "Subnet 10.0.0.0/24 (public) · t4g.micro",
                    "python3 -m http.server :80 (systemd)",
                    "serves 'hello from PrivateLink provider'",
                ], "hub", icon(EC2Instance), width=360))

            # column 4 — management
            with group("Management", "mgmt"):
                ssm = node(card("SSM Session Manager", ["2 hosts: consumer + service", "no SSH, no key pair"],
                                "mgmt", icon(SystemsManager), width=280))
                role = node(card("IAM role + instance profile", ["net-lab-pl-ssm",
                                                                 "AmazonSSMManagedInstanceCore · reused by 4-ec2"],
                                 "mgmt", icon(IAMRole), width=280))

            # column 5 — legend (colour key)
            with group("Legend", "main"):
                legend = node(card("Legend", [], "main", letter="❖", width=300,
                                   rows=[("reaches", "endpoint path up  ✓", "shared"),
                                         ("blocked", "no route between VPCs  ✘", "deny"),
                                         ("provider", "NLB + service (VPC A)", "hub"),
                                         ("consumer", "host + endpoint ENI (VPC B)", "main"),
                                         ("mgmt", "SSM / IAM", "mgmt")]))

            # data path that WORKS — solid, ✓ verdict: consumer host → ENI ══PrivateLink══ NLB → service EC2
            client >> Edge(label="  ✓ TCP to the ENI (own VPC)  ", color=ROLE["main"][0], penwidth="2.4",
                           fontname=BOLD, fontcolor=ROLE["main"][0]) >> eni
            eni >> Edge(label="  ✓ PrivateLink tunnel  ", color=ROLE["shared"][0], penwidth="2.4",
                        fontname=BOLD, fontcolor=ROLE["shared"][0]) >> pl
            pl >> Edge(label="  ✓ reaches across the overlapping 10.0.0.0/16  ", color=ROLE["shared"][0],
                       penwidth="2.4", fontname=BOLD, fontcolor=ROLE["shared"][0]) >> nlb
            nlb >> Edge(label="  ✓ to target :80  ", color=ROLE["hub"][0], penwidth="2.4",
                        fontname=BOLD, fontcolor=ROLE["hub"][0]) >> svc
            # the path that DOESN'T exist — dashed RED, ✘ verdict: direct consumer→provider private IP has no route
            client >> Edge(label=" ✘ direct to provider private IP · no route (not L3 routing) ",
                           color=ROLE["deny"][0], style="dashed", penwidth="2.4",
                           fontname=BOLD, fontcolor=ROLE["deny"][0], constraint="false") >> svc

            svc >> Edge(style="invis") >> ssm      # Management after the VPCs
            role >> Edge(style="invis") >> legend  # Legend column last
            # column ordering only: within a rank=same column (LR) a flat edge a → b puts b ABOVE a,
            # so each list below is written top → bottom and wired in reverse.
            for col in [[client, eni, b_rt], [overlap, pl], [nlb, svc], [ssm, role], [legend]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
