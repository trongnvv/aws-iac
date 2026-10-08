"""Lab 5 — VPC Peering vs TGW (non-transitive): architecture infographic.

Run:  uv run --with diagrams python architecture.py   → architecture.png
Content is data (cards / STEPS / BANNERS / CHECKS …); style lives in the helpers.
"""
import os
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EC2Instance
from diagrams.aws.management import SystemsManager
from diagrams.aws.network import RouteTable, VPCPeering
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
HEADER = ("AWS Network Lab 5 — VPC Peering vs TGW (non-transitive)",
          "hub A peers B and C (A↔B, A↔C) — but B ⊥ C: peering is non-transitive, so A will not relay "
          "across a second peering · the cheap few-VPC alternative to TGW · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("VPC", "1-vpc/", "3 VPCs A/B/C · Subnet · Internet Gateway · Route table · Security Group", "main"),
    ("Peering", "2-peering/", "2 Peering Connections (A↔B, A↔C) + routes both ways", "main"),
    ("SSM", "3-ssm/", "IAM role + instance profile (net-lab-peer-ssm)", "main"),
    ("EC2", "4-ec2/", "3 EC2 instances · t4g.micro · Amazon Linux 2023", "main"),
]
BANNERS = [
    ("Invariants:", [
        "2 Peering Connections: A↔B + A↔C — NEVER B↔C",
        "route both ways on A/B and A/C only",
        "peering is non-transitive (A won't relay B↔C)",
        "Security Group: ICMP from 10.0.0.0/8",
        "no SSH — SSM only",
        "peering has no hourly charge",
    ]),
]
CHECKS = (("Verify", "via SSM sessions"), icon(SystemsManager), [
    ("T0", "describe-instance-information", "3 hosts Online", "mgmt"),
    ("T1", "A → B", "ping 0% loss (peering A↔B)", "shared"),
    ("T2", "A → C", "ping 0% loss (peering A↔C)", "shared"),
    ("T3", "B → A, C → A", "ping 0% loss (both sides routed)", "shared"),
    ("T4", "B → C", "100% loss (non-transitive)", "deny"),
    ("T5", "C → B", "100% loss (symmetric)", "deny"),
    ("T6", "route tables", "A → 10.1+10.2 · B,C → 10.0 only · no B↔C", "deny"),
])
FOOTER = ("Cost & teardown", [
    "VPC peering has no hourly charge",
    "3× t4g.micro ≈ $0.025/h",
    "3× public IPv4 ≈ $0.015/h",
    "cross-AZ peering data $0.01/GB · same-AZ free",
    "≈ $0.04/h → cheapest lab · ./teardown.sh when done",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="1.1", fontname=FONT, label=header_html(icon(VPCPeering), *HEADER), labelloc="t",
    labeljust="c", compound="true", outputorder="edgesfirst",
)

with Diagram("", filename=OUT, outformat="png", show=False, direction="LR", graph_attr=graph_attr,
             node_attr=dict(fontname=FONT, fixedsize="false", width="0", height="0", style="", labelloc="c"),
             edge_attr=dict(fontname=FONT)):
    with box("wrapper", dict(label=section2_html(STEPS, BANNERS, CHECKS), labelloc="b",
                             labeljust="c", pencolor="transparent", bgcolor="transparent", margin="0")):
        with box("section1", dict(label=section_label(1, "AWS resources created & who reaches whom", W - 16),
                                  labelloc="t", labeljust="l", style="rounded", color="#D5DBE3",
                                  bgcolor=PANEL, margin="22")):
            # column 1 — spoke B (AWS objects; title matches content)
            with group("VPC B · 10.1.0.0/16", "main"):
                b_res = node(card("Subnet · EC2 · SG (B)", ["Subnet 10.1.0.0/24 (public)",
                                                            "EC2 t4g.micro · Amazon Linux 2023",
                                                            "Security Group: ICMP from 10/8"], "main",
                                  icon(EC2Instance), width=320))
                b_rt = node(card("Route table (B)", [], "main", icon(RouteTable), width=320,
                                 rows=[("0.0.0.0/0", "→ Internet Gateway", "main"),
                                       ("10.0.0.0/16", "→ Peering (to A)", "main")]))

            # column 2 — hub A: Peering Connections + A objects + A route table
            with group("VPC A · 10.0.0.0/16 · hub (peers both)", "hub"):
                a_pcx = node(card("VPC Peering Connection ×2", ["pcx a-b  (A ↔ B)",
                                                                "pcx a-c  (A ↔ C)",
                                                                "auto-accept · same account/region"], "hub",
                                  icon(VPCPeering), width=360))
                a_res = node(card("Subnet · EC2 · SG (A)", ["Subnet 10.0.0.0/24 (public) · EC2 t4g.micro",
                                                            "Security Group: ICMP from 10/8",
                                                            "reaches BOTH B and C"], "hub",
                                  icon(EC2Instance), width=360))
                a_rt = node(card("Route table (A)", [], "hub", icon(RouteTable), width=360,
                                 rows=[("0.0.0.0/0", "→ Internet Gateway", "hub"),
                                       ("10.1.0.0/16", "→ Peering pcx a-b (to B)", "hub"),
                                       ("10.2.0.0/16", "→ Peering pcx a-c (to C)", "hub")]))

            # column 3 — spoke C
            with group("VPC C · 10.2.0.0/16", "main"):
                c_res = node(card("Subnet · EC2 · SG (C)", ["Subnet 10.2.0.0/24 (public)",
                                                            "EC2 t4g.micro · Amazon Linux 2023",
                                                            "Security Group: ICMP from 10/8"], "main",
                                  icon(EC2Instance), width=320))
                c_rt = node(card("Route table (C)", [], "main", icon(RouteTable), width=320,
                                 rows=[("0.0.0.0/0", "→ Internet Gateway", "main"),
                                       ("10.0.0.0/16", "→ Peering (to A)", "main")]))

            # column 4 — management
            with group("Management", "mgmt"):
                ssm = node(card("SSM Session Manager", ["3 test hosts (A/B/C)", "no SSH, no key pair"],
                                "mgmt", icon(SystemsManager), width=270))
                role = node(card("IAM role + instance profile", ["net-lab-peer-ssm",
                                                                 "AmazonSSMManagedInstanceCore"], "mgmt",
                                 icon(IAMRole), width=270))

            # column 5 — legend (colour key) + the "vs TGW" contrast the title promises
            with group("Legend · Peering vs TGW", "main"):
                legend = node(card("Legend", [], "main", letter="❖", width=300,
                                   rows=[("reachable", "peering up  ✓", "shared"),
                                         ("blocked", "no peering / no route  ✘", "deny"),
                                         ("hub", "VPC A peers both", "hub"),
                                         ("mgmt", "SSM / IAM", "mgmt")]))
                vstgw = node(card("Peering vs TGW", ["TGW: transitive — B↔C relayed via the hub",
                                                     "Peering: NOT transitive (this lab)",
                                                     "rule: few VPCs → Peering · many → TGW"], "hub",
                                  icon(VPCPeering), width=300))

            # peering that EXISTS — solid green, ✓ verdict on the link
            b_res >> Edge(label="  ✓ pcx a-b  ", color=ROLE["shared"][0], penwidth="2.4", fontname=BOLD,
                          fontcolor=ROLE["shared"][0], dir="both") >> a_pcx
            a_pcx >> Edge(label="  ✓ pcx a-c  ", color=ROLE["shared"][0], penwidth="2.4", fontname=BOLD,
                          fontcolor=ROLE["shared"][0], dir="both") >> c_res
            # non-transitive gap — dashed RED straight between B and C, ✘ verdict
            b_res >> Edge(label=" ✘ no Peering Connection · no route (non-transitive) ",
                          color=ROLE["deny"][0], style="dashed", penwidth="2.4", dir="both",
                          fontname=BOLD, fontcolor=ROLE["deny"][0], constraint="false") >> c_res

            a_res >> Edge(style="invis") >> ssm    # Management after the VPCs
            role >> Edge(style="invis") >> legend  # Legend column last
            # column ordering only (LR rank=same): write top→bottom, wire in reverse.
            for col in [[b_res, b_rt], [a_pcx, a_res, a_rt], [c_res, c_rt], [ssm, role], [legend, vstgw]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
