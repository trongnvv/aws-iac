"""Lab 6 — Direct Connect → Transit Gateway (DX Gateway + Transit VIF, VPN transport stand-in): architecture infographic.

Run:  uv run --with diagrams python architecture.py   → architecture.png
Content is data (cards / STEPS / BANNERS / CHECKS …); style lives in the helpers.
AWS console names on every card (not Terraform names); ✓/✘ verdicts on the reachability edges.
"""
import os
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EC2Instance
from diagrams.aws.management import SystemsManager
from diagrams.aws.network import (
    DirectConnect, RouteTable, SiteToSiteVpn, TransitGateway, VPCCustomerGateway,
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
HEADER = ("AWS Network Lab 6 — Direct Connect → Transit Gateway",
          "On-prem router (EC2 strongSwan) ↔ Transit VIF (physical — manual) ↔ Direct Connect Gateway ↔ "
          "DX Gateway ↔ TGW association (allowed prefixes) ↔ Transit Gateway ↔ AWS VPC · a Site-to-Site VPN "
          "stands in for the physical link · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("VPC", "1-vpc/", "AWS + on-prem VPCs · Subnet · Internet Gateway · Security Group", "main"),
    ("Transit Gateway", "2-tgw/", "Transit Gateway · VPC attachment · Route table · route", "main"),
    ("Direct Connect Gateway", "3-dxgw/", "DX Gateway + DX Gateway ↔ TGW association (allowed prefixes)", "hub"),
    ("Site-to-Site VPN", "4-vpn/", "Elastic IP · Customer Gateway · VPN (2 tunnels) — transport stand-in", "main"),
    ("strongSwan", "5-strongswan/", "EC2 instance (strongSwan) · IAM role + instance profile · route", "main"),
    ("EC2", "6-ec2/", "2 EC2 test instances (AWS + on-prem)", "main"),
]
BANNERS = [
    ("Invariants:", [
        "DX-as-code = Direct Connect Gateway + DX Gateway ↔ TGW association (allowed prefixes = on-prem CIDR)",
        "data path = Site-to-Site VPN stand-in (BGP), not static routes",
        "Transit Gateway default RT assoc/prop disabled — one Route table",
        "Security Group: ICMP from 10.0.0.0/8 + 192.168.0.0/16 · no SSH — SSM only",
    ]),
    ("⚠ Built blind — verify live:", [
        "🖐 physical cross-connect + Transit VIF (BGP to Direct Connect Gateway) = manual partner step",
        "DX Gateway ↔ TGW association = associated",
        "swanctl loads both tunnels · VTI + fwmark",
        "BGP Established · ping both ways",
    ], "deny"),
]
CHECKS = (("Verify", "via SSM + AWS CLI"), icon(SystemsManager), [
    ("T0", "describe-instance-information", "3 hosts Online", "mgmt"),
    ("T1", "describe-direct-connect-gateway-associations", "DX Gateway ↔ TGW associated", "shared"),
    ("T2", "describe-vpn-connections", "≥1 tunnel UP · AcceptedRouteCount ≥ 1", "shared"),
    ("T3", "vtysh show bgp summary", "Established · PfxRcd > 0", "shared"),
    ("T4", "AWS → on-prem", "ping 0% loss", "shared"),
    ("T5", "on-prem → AWS", "ping 0% loss", "shared"),
    ("T6", "search-transit-gateway-routes", "192.168.30.0/16 · propagated", "shared"),
    ("M", "manual: request DX connection + Transit VIF", "BGP to Direct Connect Gateway (partner)", "opt"),
    ("S", "stretch: VIF types · MACsec/VPN-over-DX · DX+VPN backup", "see README", "opt"),
])
FOOTER = ("Cost & teardown", [
    "Site-to-Site VPN stand-in ≈ $0.05/h",
    "Transit Gateway ≈ $0.05/attachment-h × 2 + data",
    "Direct Connect Gateway + DX Gateway ↔ TGW association = no hourly charge (no port)",
    "3× t4g.micro ≈ $0.025/h · Elastic IP + public IPv4 ≈ $0.005/h × 4",
    "≈ $0.25/h → ./teardown.sh (VPN bills until 4-vpn destroyed)",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="0.9", fontname=FONT, label=header_html(icon(DirectConnect), *HEADER), labelloc="t",
    labeljust="c", compound="true", outputorder="edgesfirst",
)

with Diagram("", filename=OUT, outformat="png", show=False, direction="LR", graph_attr=graph_attr,
             node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0", style="", labelloc="c"),
             edge_attr=dict(fontname=FONT)):
    # invisible wrapper: its bottom label carries every full-width row (section 2 + footer)
    with box("wrapper", dict(label=section2_html(STEPS, BANNERS, CHECKS), labelloc="b",
                             labeljust="c", pencolor="transparent", bgcolor="transparent", margin="0")):
        with box("section1", dict(label=section_label(1, "Topology & traffic flow — who reaches whom", W - 16),
                                  labelloc="t", labeljust="l", style="rounded", color="#D5DBE3",
                                  bgcolor=PANEL, margin="22")):
            # column 1 — simulated on-prem
            with group("“On-prem” VPC · 192.168.30.0/16 (simulated)", "opt"):
                onprem = node(card("EC2 instance (on-prem test host)", ["Subnet 192.168.0.0/24 (public) · t4g.micro",
                                                        "Route table: 10.30.0.0/16 → strongSwan ENI",
                                                        "Route table: 0.0.0.0/0 → Internet Gateway (SSM)"], "main",
                                   icon(EC2Instance)))
                cgw_box = node(card("EC2 instance (strongSwan)", [
                    "t4g.micro · Elastic IP · source/dest check off",
                    "IKEv2 · vti1 / vti2 (fwmark 100 / 200) · MTU 1419",
                    "FRR BGP ASN 65000 · advertises 192.168.30.0/16",
                    "⚠ real DX: this box is the Transit VIF BGP peer",
                ], "opt", icon(EC2Instance), width=340))

            # column 2 — the Transit VIF: a physical manual step, stood in by a Site-to-Site VPN
            with group("Transit VIF (physical — manual) · Site-to-Site VPN stand-in (BGP)", "shared"):
                phys = node(card("🖐 Transit VIF (physical — manual)", ["partner / manual — NOT IaC",
                                                               "request DX connection + Transit VIF",
                                                               "BGP to the Direct Connect Gateway"], "deny",
                                 letter="M", width=320))
                t1 = node(card("Site-to-Site VPN · Tunnel 1", ["IPsec IKEv2 · own PSK + outside IP",
                                            "inside /30 (169.254.x.x) · BGP to VGW",
                                            "preferred path"], "shared", letter="1", width=320))
                t2 = node(card("Site-to-Site VPN · Tunnel 2", ["IPsec IKEv2 · own PSK + outside IP",
                                            "inside /30 (169.254.x.x) · BGP to VGW",
                                            "backup (DPD 10s · BGP timers 10/30)"], "shared", letter="2",
                                width=320))
                cgw = node(card("Customer Gateway", ["AWS record of the on-prem peer",
                                                     "Elastic IP · BGP ASN 65000"], "shared",
                                icon(VPCCustomerGateway), width=320))

            # column 3 — Direct Connect Gateway (the DX-as-code control plane)
            with group("Direct Connect Gateway · global, logical (as-code half)", "hub"):
                dxgw = node(card("Direct Connect Gateway", ["amazon-side ASN 64513",
                                                "a Transit VIF BGP-peers here"], "hub",
                                 icon(DirectConnect), width=340))
                assoc = node(card("DX Gateway ↔ TGW association", ["associated gateway = Transit Gateway",
                                                             "allowed prefixes = [192.168.30.0/16]"], "hub",
                                  icon(RouteTable), width=340,
                                  rows=[("192.168.30.0/16", "allowed → Transit Gateway", "hub")]))

            # column 4 — transit gateway
            with group("Transit Gateway · default RT assoc/prop disabled", "hub"):
                tgw = node(card("Transit Gateway", ["amazon-side ASN 64512", "VPN ECMP support = enable"], "hub",
                                icon(TransitGateway), width=340))
                main_rt = node(card("Route table (Transit Gateway)", ["assoc: AWS VPC, VPN, DXGW attachments"], "hub",
                                    icon(RouteTable), width=340,
                                    rows=[("10.30.0.0/16", "AWS VPC · propagated", "hub"),
                                          ("192.168.30.0/16", "VPN · propagated (BGP)", "hub")]))

            # column 5 — cloud VPC
            with group("VPC AWS · 10.30.0.0/16", "main"):
                aws_host = node(card("EC2 instance (AWS test host)", ["Subnet 10.30.0.0/24 (public) · t4g.micro",
                                                       "Route table: 192.168.30.0/16 → Transit Gateway",
                                                       "Route table: 0.0.0.0/0 → Internet Gateway (SSM)"], "main",
                                     icon(EC2Instance), width=330))

            # column 6 — management
            with group("Management", "mgmt"):
                ssm = node(card("SSM Session Manager", ["3 hosts: 2 test + strongSwan", "no SSH, no key pair"],
                                "mgmt", icon(SystemsManager), width=300))
                role = node(card("IAM role + instance profile", ["net-lab-dx-ssm",
                                                    "AmazonSSMManagedInstanceCore"], "mgmt", icon(IAMRole),
                                 width=300))

            # column 7 — legend (colour + verdict key)
            with group("Legend", "main"):
                legend = node(card("Legend", [], "main", letter="❖", width=300,
                                   rows=[("reachable", "VPN transport up  ✓", "shared"),
                                         ("blocked", "no route / no peer  ✘", "deny"),
                                         ("hub", "DX Gateway · Transit Gateway", "hub"),
                                         ("manual step", "🖐 physical Transit VIF", "deny"),
                                         ("mgmt", "SSM / IAM", "mgmt")]))

            # working data path (VPN stand-in): onprem host → strongSwan → Tunnels → DX Gateway → assoc → TGW → AWS VPC
            onprem >> Edge(label="  ✓ reaches AWS  ", color=ROLE["main"][0], penwidth="2.0", fontname=BOLD,
                           fontcolor=ROLE["main"][0]) >> cgw_box
            flow(cgw_box, t1, "shared")
            flow(cgw_box, t2, "shared", dashed=True)
            t1 >> Edge(label="  ✓ BGP · tunnels UP  ", color=ROLE["shared"][0], penwidth="2.4", fontname=BOLD,
                       fontcolor=ROLE["shared"][0]) >> dxgw
            flow(t2, dxgw, "shared", dashed=True)
            dxgw >> Edge(label="  ✓ DX Gateway ↔ TGW associated  ", color=ROLE["hub"][0], penwidth="2.4",
                         fontname=BOLD, fontcolor=ROLE["hub"][0]) >> assoc
            flow(assoc, tgw, "hub")
            tgw >> Edge(label="  ✓ on-prem CIDR propagated  ", color=ROLE["hub"][0], penwidth="2.0",
                        fontname=BOLD, fontcolor=ROLE["hub"][0]) >> aws_host
            # the physical Transit VIF — dashed RED ⚠ manual step, distinct from the working VPN transport
            cgw_box >> Edge(label=" ✘ physical cross-connect · Transit VIF — partner / manual, not IaC ",
                            color=ROLE["deny"][0], style="dashed", penwidth="2.4", dir="both",
                            fontname=BOLD, fontcolor=ROLE["deny"][0], constraint="false") >> dxgw

            aws_host >> Edge(style="invis") >> ssm    # keeps Management after the VPCs
            role >> Edge(style="invis") >> legend     # Legend column last
            # column ordering only: within a rank=same column (LR) a flat edge a → b puts b ABOVE a,
            # so each list below is written top → bottom and wired in reverse.
            for col in [[onprem, cgw_box], [phys, t1, t2, cgw], [dxgw, assoc], [tgw, main_rt], [aws_host], [ssm, role], [legend]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
