"""Lab 6 — VPC Lattice (L7 service-to-service across VPCs): architecture infographic.

Run:  uv run --with diagrams python architecture.py   → architecture.png
Content is data (cards / STEPS / BANNERS / CHECKS …); style lives in the helpers.
"""
import os
from pathlib import Path

import diagrams
from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import EC2Instance
from diagrams.aws.management import SystemsManager
from diagrams.aws.network import ELB, PublicSubnet, VPCElasticNetworkInterface
from diagrams.aws.security import IAMPermissions, IAMRole

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


# ── content (from 1-vpc … 4-ec2 *.tf, 3-service/service.tf user_data and README.md) ─────────────
HEADER = ("AWS Network Lab 7 — VPC Lattice (L7 service-to-service)",
          "One Lattice service network associates VPC A + VPC B (both 10.0.0.0/16); client in A reaches the "
          "service in B by Lattice DNS at L7 — no peering/TGW, no L3 routing · IAM auth · ap-southeast-1")

STEPS = [  # (name, folder, builds, role)
    ("VPC", "1-vpc/", "VPC A + B · both 10.0.0.0/16 (overlap) · IGW · SG", "main"),
    ("Service network", "2-service-network/", "net (AWS_IAM) · allow-all policy · assoc both VPCs", "main"),
    ("Service", "3-service/", "SSM role · svc EC2 (B) · TG · listener · svc↔net", "main"),
    ("EC2", "4-ec2/", "client EC2 in A · curls the Lattice DNS name", "main"),
]
BANNERS = [
    ("Invariants:", [
        "L7 (HTTP), not L3 — no route tables / CIDR planning",
        "overlapping 10.0.0.0/16 is a non-issue (link-local DNS)",
        "one service network associates BOTH VPCs",
        "auth_type = AWS_IAM (allow-all base, tighten per-service)",
        "no SSH — SSM only",
    ]),
    ("⚠ Built blind — verify live:", [
        "aws_vpclattice_* args confirm on apply",
        "plain curl works with Principal:\"*\" or SigV4 enforced?",
        "TG config/health_check nesting + casing",
        "dns_entry[0].domain_name is the DNS attr",
        "VPC-side SG may need the Lattice managed prefix",
    ], "deny"),
]
CHECKS = (("Verify", "via SSM + AWS CLI"), icon(SystemsManager), [
    ("T0", "describe-instance-information", "client (VPC A) Online", "mgmt"),
    ("T1", "list-service-network-vpc-associations", "2 assoc · both ACTIVE", "shared"),
    ("T2", "get-service + svc↔net assoc", "service ACTIVE + associated · target HEALTHY", "shared"),
    ("T3", "client A → curl http://$DNS", "reaches B across 10.0/16 overlap · no peering/TGW", "shared"),
    ("T4", "tighten per-service auth policy", "unauthorized → 403", "deny"),
    ("T4", "widen back to allowed principal", "allowed → 200 (SigV4)", "opt"),
])
FOOTER = ("Cost & teardown", [
    "VPC Lattice ≈ $0.025/h per service + per-request (~$0.10/1M) + data (~$0.01/GB)",
    "2× t4g.micro ≈ $0.017/h",
    "2× public IPv4 ≈ $0.01/h",
    "≈ $0.05/h → ./teardown.sh (billed hourly even idle)",
])

# ── diagram ──────────────────────────────────────────────────────────────────────────────────────
OUT = os.path.splitext(os.path.basename(__file__))[0]
graph_attr = dict(
    rankdir="LR", splines="ortho", newrank="true", bgcolor=CANVAS, pad="0.5", nodesep="0.35",
    ranksep="0.9", fontname=FONT, label=header_html(icon(ELB), *HEADER), labelloc="t",
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
            # column 1 — VPC A (client)
            with group("VPC A · 10.0.0.0/16 · client", "main"):
                client = node(card("client test host", ["public 10.0.0.0/24 · t4g.micro",
                                                        "SSM in, then curl http://<lattice DNS>",
                                                        "no route to B — only Lattice reaches it"], "main",
                                   icon(EC2Instance), width=330))
                a_assoc = node(card("VPC A association", ["service network injects the resolver",
                                                          "+ link-local data path into VPC A",
                                                          "assoc SG allows HTTP:80"], "main",
                                    icon(PublicSubnet)))

            # column 2 — the Lattice service network (the backplane)
            with group("Lattice Service Network · net-lab-lattice", "hub"):
                net = node(card("Service Network", ["auth_type = AWS_IAM",
                                                    "associates BOTH VPC A + VPC B",
                                                    "replaces peering/TGW routing (L7)"], "hub",
                                icon(ELB), width=360))
                net_policy = node(card("network auth policy", ["allow-all (Principal: \"*\")",
                                                               "vpc-lattice-svcs:Invoke"], "hub",
                                       icon(IAMPermissions), width=360))
                dns = node(card("service DNS (L7)", [
                    "svc-b-….vpc-lattice-svcs.<region>.on.aws",
                    "resolves to link-local 169.254.x.x",
                    "overlapping 10.0/16 irrelevant"], "shared", letter="⬡", width=360))

            # column 3 — the Lattice service (published to the network)
            with group("Lattice Service · net-lab-lattice-svc-b", "shared"):
                svc = node(card("Service B", ["auth_type = AWS_IAM",
                                              "svc↔network association publishes it",
                                              "dns_entry[0].domain_name"], "shared",
                                icon(ELB), width=330))
                svc_policy = node(card("service auth policy", ["allow-all base (Principal: \"*\")",
                                                               "tighten → specific role ARN (T4)",
                                                               "unauthorized → 403 · allowed → 200"], "opt",
                                       icon(IAMPermissions), width=330))
                listener = node(card("HTTP:80 listener", ["default_action forward → TG",
                                                          "(stretch: /v1 · /v2 listener rules)"], "shared",
                                     letter="L", width=330))
                tg = node(card("target group (INSTANCE)", ["port 80 · HTTP · HTTP1 · vpc_id = B",
                                                           "health_check / :80 matcher 200",
                                                           "attach service EC2 → HEALTHY"], "shared",
                                icon(VPCElasticNetworkInterface), width=330))

            # column 4 — VPC B (service)
            with group("VPC B · 10.0.0.0/16 · SAME CIDR!", "main"):
                b_assoc = node(card("VPC B association", ["injects resolver + link-local path",
                                                          "assoc SG allows HTTP:80"], "main",
                                    icon(PublicSubnet)))
                service_ec2 = node(card("service test host", ["public 10.0.0.0/24 · t4g.micro",
                                                              "python3 -m http.server 80",
                                                              "'hello from service B … 10.0.0.0/16'"], "main",
                                        icon(EC2Instance), width=330))

            # column 5 — management
            with group("Management", "mgmt"):
                ssm = node(card("SSM Session Manager", ["2 hosts: client (A) + service (B)",
                                                        "no SSH, no key pair"], "mgmt",
                                icon(SystemsManager), width=270))
                role = node(card("net-lab-lattice-ssm", ["IAM role + instance profile",
                                                         "created in 3-service, reused by 4-ec2",
                                                         "AmazonSSMManagedInstanceCore"], "mgmt",
                                 icon(IAMRole), width=270))

            # data path: client (A) → Lattice DNS (link-local) → service network → service (B)
            flow(client, a_assoc, "main")
            flow(a_assoc, dns, "shared")
            flow(dns, net, "hub")
            flow(net, svc, "shared")
            flow(svc, listener, "shared")
            flow(listener, tg, "shared")
            flow(tg, service_ec2, "main")
            flow(b_assoc, net, "main", dashed=True)  # VPC B associated to the network

            service_ec2 >> Edge(style="invis") >> ssm  # keeps Management as the last column
            # column ordering only: within a rank=same column (LR) a flat edge a → b puts b ABOVE a,
            # so each list below is written top → bottom and wired in reverse.
            for col in [[client, a_assoc], [net, net_policy, dns], [svc, svc_policy, listener, tg],
                        [b_assoc, service_ec2], [ssm, role]]:
                for upper, lower in zip(col, col[1:]):
                    lower >> Edge(style="invis") >> upper
