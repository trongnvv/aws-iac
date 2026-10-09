"""Lab 4 — Route 53 Resolver (two-way hybrid DNS): architecture infographic.

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
    Route53, Route53HostedZone, VPCElasticNetworkInterface, VPCPeering, PublicSubnet,
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
    bg = "white"  # white cards; role shown by the colored border + pill
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


# ── content (from 1-vpc … 4-ec2 *.tf, 3-onprem-dns/user_data.sh.tftpl and README.md) ──────────
HEADER = ("AWS Network Lab 4 — Route 53 Resolver (two-way hybrid DNS)",
          "aws VPC 10.20/16 ⇄ VPC peering ⇄ “on-prem” VPC 192.168/16 (dnsmasq) · outbound EP forwards "
          "corp.local to on-prem · inbound EP + PHZ serve aws.internal to on-prem · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("VPC", "1-vpc/", "aws (2 AZ) + onprem VPCs · IGW/RT · peering + routes · SGs", "main"),
    ("DNS", "2-dns/", "PHZ aws.internal · inbound + outbound EP · corp.local rule", "main"),
    ("on-prem DNS", "3-onprem-dns/", "dnsmasq EC2 @192.168.0.53 · SSM role", "main"),
    ("EC2", "4-ec2/", "2 test hosts (aws + onprem)", "main"),
]
BANNERS = [
    ("Invariants:", [
        "two-way: outbound EP forwards corp.local · inbound EP + PHZ serve aws.internal",
        "non-overlapping CIDRs (10.20 ⊥ 192.168) so peering routes the DNS packets",
        "on-prem DNS pinned static 192.168.0.53 (breaks the apply chicken-and-egg)",
        "no SSH — SSM only",
    ]),
    ("⚠ Built blind — verify live:", [
        "dnsmasq config (address= + server=/aws.internal/) unverified",
        "resolver endpoints ~5 min to Operational",
        "early dig before Operational → SERVFAIL",
        "inbound IPs templated into layer 3",
    ], "deny"),
]
CHECKS = (("Verify", "via SSM + AWS CLI"), icon(SystemsManager), [
    ("T0", "describe-instance-information", "3 hosts Online", "mgmt"),
    ("T1", "list-resolver-endpoints", "both EP OPERATIONAL (~5 min)", "shared"),
    ("T2", "systemctl status dnsmasq", "active (running) · corp-local.conf", "shared"),
    ("T3", "aws: dig host1.corp.local", "→ 192.168.0.80 (outbound EP)", "shared"),
    ("T4", "onprem: dig test.aws.internal", "→ 10.20.99.99 (inbound + PHZ)", "shared"),
    ("S1", "stretch: reverse DNS (PTR)", "dig -x both ways resolve", "opt"),
])
FOOTER = ("Cost & teardown", [
    "resolver ENIs ≈ $0.125/ENI-h × 4 ≈ $0.50/h  ← the pricey one, destroy promptly",
    "3× t4g.micro ≈ $0.075/h",
    "3× public IPv4 ≈ $0.015/h",
    "≈ $0.60/h → ./teardown.sh (destroy 2-dns to stop the resolver ENI bill)",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="0.9", fontname=FONT, label=header_html(icon(Route53), *HEADER), labelloc="t",
    labeljust="c", compound="true", outputorder="edgesfirst",
)

with Diagram("", filename=OUT, outformat="png", show=False, direction="LR", graph_attr=graph_attr,
             node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0", style="", labelloc="c"),
             edge_attr=dict(fontname=FONT)):
    # section-1 label = title + a plain-text legend line (no box) so the arrows/colors are explained
    sep = txt("      ", 11, MUTED)
    LEGEND = (
        txt("Legend:  ", 11, INK, bold=True)
        + txt("──▶ AWS→on-prem (corp.local via outbound EP)", 11, ROLE["shared"][0], bold=True) + sep
        + txt("╌╌▶ on-prem→AWS (aws.internal via inbound EP → PHZ)", 11, ROLE["hub"][0], bold=True) + sep
        + txt("VPC peering link", 11, ROLE["hub"][0], bold=True) + sep
        + txt("main", 11, ROLE["main"][0], bold=True) + txt(" · ", 11, MUTED)
        + txt("hub", 11, ROLE["hub"][0], bold=True) + txt(" · ", 11, MUTED)
        + txt("shared", 11, ROLE["shared"][0], bold=True) + txt(" · ", 11, MUTED)
        + txt("on-prem", 11, ROLE["opt"][0], bold=True) + txt(" · ", 11, MUTED)
        + txt("mgmt", 11, ROLE["mgmt"][0], bold=True))
    sec1_label = (f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="2" WIDTH="{W - 16}">'
                  f'<TR><TD ALIGN="LEFT">{section_label(1, "Topology & traffic flow", W - 16)[1:-1]}</TD></TR>'
                  f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">{LEGEND}</TD></TR></TABLE>>')
    # invisible wrapper: its bottom label carries every full-width row (section 2 + footer)
    with box("wrapper", dict(label=section2_html(STEPS, BANNERS, CHECKS), labelloc="b",
                             labeljust="c", pencolor="transparent", bgcolor="transparent", margin="0")):
        with box("section1", dict(label=sec1_label,
                                  labelloc="t", labeljust="l", style="rounded", color="#D5DBE3",
                                  bgcolor=PANEL, margin="22")):
            # column 1 — AWS VPC: resolver endpoints + PHZ + test host
            with group("VPC aws · 10.20.0.0/16 · 2 AZs", "main"):
                out_ep = node(card("Resolver OUTBOUND endpoint", [
                    "2 ENIs (subnet a + b) · SG egress 53 → on-prem",
                    "AWS→on-prem egress path for corp.local",
                ], "shared", icon(VPCElasticNetworkInterface)))
                corp_rule = node(card("corp.local FORWARD rule", [
                    "rule_type FORWARD → outbound EP",
                    "target 192.168.0.53:53 · assoc aws VPC",
                ], "shared", icon(Route53)))
                inb_ep = node(card("Resolver INBOUND endpoint", [
                    "2 ENIs (subnet a + b) · SG ingress 53 from on-prem",
                    "on-prem→AWS entry for aws.internal",
                ], "shared", icon(VPCElasticNetworkInterface)))
                phz = node(card("PHZ aws.internal", [
                    "private hosted zone · assoc aws VPC",
                    "test.aws.internal A → 10.20.99.99",
                ], "hub", icon(Route53HostedZone)))
                aws_host = node(card("aws test host", ["public 10.20.0.0/24 · t4g.micro",
                                                       "dig host1.corp.local", "SSM, no SSH"], "main",
                                     icon(EC2Instance)))

            # column 2 — the peering link that carries the DNS packets
            with group("VPC Peering · aws ↔ on-prem", "hub"):
                pcx = node(card("VPC peering", [
                    "non-overlapping CIDRs 10.20 ⊥ 192.168",
                    "RT aws: 192.168/16 → pcx",
                    "RT onprem: 10.20/16 → pcx",
                    "carries forwarded DNS packets",
                ], "hub", icon(VPCPeering)))

            # column 3 — simulated on-prem VPC: dnsmasq + test host
            with group("“On-prem” VPC · 192.168.0.0/16 (simulated)", "opt"):
                dns = node(card("dnsmasq DNS server", [
                    "static 192.168.0.53 · t4g.micro",
                    "authoritative corp.local (host1 → .80)",
                    "forwards aws.internal → inbound EP IPs",
                    "owns shared SSM role",
                ], "opt", icon(EC2Instance)))
                onprem_host = node(card("onprem test host", ["public 192.168.0.0/24 · t4g.micro",
                                                             "resolv.conf → 192.168.0.53",
                                                             "dig test.aws.internal"], "main",
                                        icon(EC2Instance)))

            # column 4 — management
            with group("Management", "mgmt"):
                ssm = node(card("SSM Session Manager", ["3 hosts: 2 test + dnsmasq", "no SSH, no key pair"],
                                "mgmt", icon(SystemsManager)))
                role = node(card("net-lab-r53-ssm", ["IAM role + instance profile",
                                                     "AmazonSSMManagedInstanceCore"], "mgmt", icon(IAMRole)))

            # AWS → on-prem (corp.local): host → rule → outbound EP → peering → dnsmasq
            flow(aws_host, corp_rule, "main")
            flow(corp_rule, out_ep, "shared")
            flow(out_ep, pcx, "shared")
            flow(pcx, dns, "shared")
            # on-prem → AWS (aws.internal): dnsmasq → peering → inbound EP → PHZ
            flow(dns, pcx, "main", dashed=True)
            flow(pcx, inb_ep, "main", dashed=True)
            flow(inb_ep, phz, "hub", dashed=True)
            # onprem test host asks dnsmasq
            flow(onprem_host, dns, "main", constraint=False)

            dns >> Edge(style="invis") >> ssm  # keeps Management as the last column
            # column ordering only: within a rank=same column (LR) a flat edge a → b puts b ABOVE a,
            # so each list below is written top → bottom and wired in reverse.
            for col in [[out_ep, corp_rule, inb_ep, phz, aws_host], [pcx],
                        [dns, onprem_host], [ssm, role]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
