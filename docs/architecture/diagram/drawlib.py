"""Drawing primitives shared by the architecture diagram generators (generate.py, generate_tiers.py).

Every call draws twice from the same coordinates: an SVG element (for GitHub, the PNG and the docs) and a
draw.io (mxGraph) cell, so the .drawio files stay editable shape by shape and never drift from the SVG.
Call reset() between diagrams when one script draws several.
"""
from html import escape


# ---------------------------------------------------------------- palette (light, print friendly)
C = {
    "bg": "#ffffff",
    "ink": "#1b2430",
    "muted": "#5b6675",
    "line": "#8a94a3",
    # ownership
    "pt_fill": "#eaf2fd", "pt_stroke": "#3b74c4",        # Platform Engineering (P&T)
    "plat_fill": "#e7f6f1", "plat_stroke": "#1f8a68",    # AI Advisory shared platform, no client data
    "cli_fill": "#fbf3e6", "cli_stroke": "#b7791f",      # per-client, client data
    "ext_fill": "#f3f1f8", "ext_stroke": "#6b5ca5",      # users / external / GitHub
    # inner elements
    "vnet_fill": "#fffaf2", "vnet_stroke": "#c9954a",
    "subnet_fill": "#ffffff", "subnet_stroke": "#d9b98a",
    "chip_fill": "#ffffff", "chip_stroke": "#c3cad4",
    "sec": "#c0392b",     # security-relevant highlights
    "flow_user": "#6b5ca5", "flow_model": "#b7791f", "flow_egress": "#c0392b",
    "flow_mgmt": "#1f8a68", "flow_logs": "#3b74c4",
}
FONT = "Segoe UI, Helvetica, Arial, sans-serif"
out = []    # SVG elements
CELLS = []  # draw.io (mxGraph) cells, drawn from the same calls so both outputs stay in step
_MUTE = [False]  # True while a chip draws its parts, because a chip is one editable draw.io cell

# draw.io's built-in Azure icon set (img/lib/azure2/...). First match on a chip title wins.
ICONS = [
    ("Azure Firewall", "networking/Firewalls"), ("App Gateway", "networking/Application_Gateways"),
    ("ExpressRoute", "networking/Virtual_Network_Gateways"), ("VPN gateway", "networking/Virtual_Network_Gateways"),
    ("Private DNS Resolver", "networking/DNS_Private_Resolver"),
    ("privatelink", "networking/DNS_Zones"), ("Linked per-client zones", "networking/DNS_Zones"),
    ("DNS (P&T)", "networking/DNS_Zones"), ("Azure Bastion", "networking/Bastions"),
    ("DDoS", "networking/DDoS_Protection_Plans"), ("Azure Front Door", "networking/Front_Doors"),
    ("pe-", "networking/Private_Endpoint"), ("Azure OpenAI", "ai_machine_learning/Azure_OpenAI"),
    ("AOAI centralus", "ai_machine_learning/Azure_OpenAI"), ("Azure AI Search", "app_services/Search_Services"),
    ("Content Safety", "ai_machine_learning/Content_Safety"), ("Key Vault", "security/Key_Vaults"),
    ("Storage", "storage/Storage_Accounts"), ("Terraform state", "storage/Storage_Accounts"),
    ("AKS", "containers/Kubernetes_Services"), ("Container Apps environment", "other/Container_App_Environments"),
    ("ca-<client>", "other/Worker_Container_App"), ("Container Apps Jobs", "other/Worker_Container_App"),
    ("Azure Container Registry", "containers/Container_Registries"), ("AI gateway", "integration/API_Management_Services"),
    ("id-", "identity/Managed_Identities"), ("APIM system MI", "identity/Managed_Identities"),
    ("Per-client deployment", "identity/Managed_Identities"), ("Per-client plan", "identity/Managed_Identities"),
    ("Log Analytics", "analytics/Log_Analytics_Workspaces"), ("Platform Log Analytics", "analytics/Log_Analytics_Workspaces"),
    ("Alerts", "management_governance/Alerts"), ("Azure Policy", "management_governance/Policy"),
    ("Policy as code", "management_governance/Policy"), ("Entra ID groups", "identity/Groups"),
    ("Defender", "security/Azure_Defender"), ("sub:", "general/Subscriptions"), (" MG", "general/Management_Groups"),
    ("Central ops workbook", "general/Workbooks"), ("Managed NGINX", "networking/Route_Tables"),
]


def _cell(value, style, x, y, w, h, vertex=True):
    CELLS.append(f'<mxCell id="c{len(CELLS) + 2}" value="{escape(value)}" style="{style}" '
                 f'{"vertex" if vertex else "edge"}="1" parent="1">'
                 f'<mxGeometry x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>')


def slot():
    """Reserve a z-order position for a box whose height is only known after its contents are laid out."""
    out.append("")
    CELLS.append("")
    return len(out) - 1, len(CELLS) - 1


def rect(x, y, w, h, fill, stroke, rx=8, dash=None, sw=1.5, opacity=1, at=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    if not _MUTE[0]:
        style = (f"rounded=1;absoluteArcSize=1;arcSize={rx * 2};whiteSpace=wrap;html=1;fillColor={fill};"
                 f"strokeColor={stroke};strokeWidth={sw};" + ("dashed=1;dashPattern=5 3;" if dash else ""))
        if at is not None:
            n = len(CELLS)
            _cell("", style, x, y, w, h)
            CELLS[at[1]] = CELLS.pop().replace(f'id="c{n + 2}"', f'id="s{at[1]}"')
        else:
            _cell("", style, x, y, w, h)
    if at is not None:
        out[at[0]] = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
                      f'stroke="{stroke}" stroke-width="{sw}"{d} opacity="{opacity}"/>')
        return
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
               f'stroke="{stroke}" stroke-width="{sw}"{d} opacity="{opacity}"/>')


def text(x, y, s, size=13, weight=400, anchor="start", fill=None, italic=False):
    st = ' font-style="italic"' if italic else ""
    if not _MUTE[0]:
        tw = len(s) * size * 0.56 + 6
        tx = {"start": x, "middle": x - tw / 2, "end": x - tw}[anchor]
        fs = (1 if weight >= 600 else 0) + (2 if italic else 0)
        _cell(s, f"text;html=1;align={ {'start': 'left', 'middle': 'center', 'end': 'right'}[anchor] };"
                 f"verticalAlign=middle;spacing=0;whiteSpace=nowrap;fontSize={size};fontStyle={fs};"
                 f"fontColor={fill or C['ink']};", tx, y - size - 1, tw, size + 6)
    out.append(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
               f'text-anchor="{anchor}" fill="{fill or C["ink"]}"{st}>{escape(s)}</text>')


def lines(x, y, items, size=12, gap=None, fill=None, weight=400):
    gap = gap or size + 4
    for i, s in enumerate(items):
        text(x, y + i * gap, s, size, weight, fill=fill)


CHAR = 0.5  # average glyph width as a fraction of font size (conservative for fallback fonts)


def wrap(s, width, size):
    """Greedy word wrap so text never overflows its box."""
    maxc = max(8, int(width / (size * CHAR)))
    words, cur, res = s.split(" "), "", []
    for wd in words:
        if cur and len(cur) + 1 + len(wd) > maxc:
            res.append(cur)
            cur = wd
        else:
            cur = f"{cur} {wd}" if cur else wd
    if cur:
        res.append(cur)
    return res


def chip_h(w, title, sub=(), title_size=13, sub_size=11):
    tl = wrap(title, w - 16, title_size * 1.12)  # bold runs wider
    sl = [ln for s_ in sub for ln in wrap(s_, w - 16, sub_size)]
    return 10 + len(tl) * (title_size + 4) + len(sl) * (sub_size + 4) + 8


def chip(x, y, w, h, title, sub=(), fill=None, stroke=None, title_size=13, sub_size=11, sec=False):
    """Box with a bold title and muted detail lines. h=None sizes the box to its wrapped content.
    Returns the height used."""
    tl = wrap(title, w - 16, title_size * 1.12)  # bold runs wider
    sl = [ln for s_ in sub for ln in wrap(s_, w - 16, sub_size)]
    need = 10 + len(tl) * (title_size + 4) + len(sl) * (sub_size + 4) + 8
    h = max(h or 0, need)
    fill_, stroke_, sw_ = fill or C["chip_fill"], C["sec"] if sec else (stroke or C["chip_stroke"]), 2 if sec else 1.2
    # draw.io: one box with an HTML label, so the whole chip is a single editable shape
    icon = next((path for key, path in ICONS if key in title), None)
    label = (f'<b style="font-size:{title_size}px">{escape(title)}</b>'
             + (f'<br><span style="font-size:{sub_size}px;color:{C["muted"]}">'
                + "<br>".join(escape(t) for t in sub) + "</span>" if sub else ""))
    _cell(label, f"rounded=1;absoluteArcSize=1;arcSize=12;whiteSpace=wrap;html=1;fillColor={fill_};"
                 f"strokeColor={stroke_};strokeWidth={sw_};align=left;verticalAlign=top;spacingLeft=6;"
                 f"spacingTop=0;spacingRight={26 if icon else 4};fontColor={C['ink']};", x, y, w, h)
    if icon:
        _cell("", f"image;aspect=fixed;html=1;points=[];image=img/lib/azure2/{icon}.svg;", x + w - 24, y + 5, 18, 18)
    _MUTE[0] = True
    rect(x, y, w, h, fill_, stroke_, rx=6, sw=sw_)
    lines(x + 8, y + 8 + title_size, tl, title_size, weight=600)
    lines(x + 8, y + 12 + len(tl) * (title_size + 4) + sub_size, sl, sub_size, fill=C["muted"])
    _MUTE[0] = False
    return h


def badge(x, y, n, color):
    _cell(str(n), f"ellipse;html=1;fillColor={color};strokeColor=none;fontColor=#ffffff;fontStyle=1;fontSize=13;",
          x - 12, y - 12, 24, 24)
    out.append(f'<circle cx="{x}" cy="{y}" r="12" fill="{color}"/>')
    _MUTE[0] = True
    text(x, y + 4.5, str(n), 13, 700, "middle", "#ffffff")
    _MUTE[0] = False


def arrow(points, color, dash=None, sw=2.2, head=True):
    d = "M " + " L ".join(f"{px} {py}" for px, py in points)
    da = f' stroke-dasharray="{dash}"' if dash else ""
    mk = f' marker-end="url(#ah-{color[1:]})"' if head else ""
    (sx_, sy_), (tx_, ty_) = points[0], points[-1]
    way = "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in points[1:-1])
    CELLS.append(
        f'<mxCell id="c{len(CELLS) + 2}" value="" style="edgeStyle=none;html=1;rounded=0;strokeColor={color};'
        f'strokeWidth={sw};endArrow={"block" if head else "none"};endFill=1;'
        + ("dashed=1;" if dash else "") + f'" edge="1" parent="1"><mxGeometry relative="1" as="geometry">'
        f'<mxPoint x="{sx_}" y="{sy_}" as="sourcePoint"/><mxPoint x="{tx_}" y="{ty_}" as="targetPoint"/>'
        + (f'<Array as="points">{way}</Array>' if way else "") + "</mxGeometry></mxCell>")
    out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}"{da}{mk} '
               f'stroke-linejoin="round"/>')


PENDING = []  # main-band columns whose height is set once the tallest client column is known


def section(x, y, w, h, title, kind, subtitle=None):
    fill, stroke = C[f"{kind}_fill"], C[f"{kind}_stroke"]
    if h is None:
        PENDING.append((slot(), x, y, w, fill, stroke))
    else:
        rect(x, y, w, h, fill, stroke, rx=12, sw=2)
    text(x + 14, y + 26, title, 17, 700, fill=stroke)
    if subtitle:
        text(x + 14, y + 45, subtitle, 12, 400, fill=C["muted"])


def reset():
    """Start a new diagram in the same process."""
    out.clear()
    CELLS.clear()
    PENDING.clear()
    _MUTE[0] = False


def open_canvas(w, h=0):
    """SVG header, arrow markers and background. Returns nothing; out[0] is rewritten by save() once H is known."""
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">')
    out.append("<defs>")
    for col in sorted({C["flow_user"], C["flow_model"], C["flow_egress"], C["flow_mgmt"], C["flow_logs"], C["line"]}):
        out.append(f'<marker id="ah-{col[1:]}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
                   f'markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
    out.append("</defs>")
    out.append(f'<rect width="100%" height="100%" fill="{C["bg"]}"/>')


def save(base, w, h, diagram_id, name):
    """Write <base>.svg, <base>.drawio and <base>.drawio.svg (pathlib.Path without suffix)."""
    out.append("</svg>")
    out[0] = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
    svg, drawio, drawio_svg = (base.with_name(base.name + s) for s in (".svg", ".drawio", ".drawio.svg"))
    svg.write_text("\n".join(out), encoding="utf-8")
    mxfile = (
        f'<mxfile host="{base.name}" type="device"><diagram id="{diagram_id}" name="{escape(name)}">'
        f'<mxGraphModel dx="{w}" dy="{h}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
        f'fold="1" page="1" pageScale="1" pageWidth="{w}" pageHeight="{h}" background="{C["bg"]}" math="0" shadow="0">'
        '<root><mxCell id="0"/><mxCell id="1" parent="0"/>' + "".join(c for c in CELLS if c)
        + "</root></mxGraphModel></diagram></mxfile>")
    drawio.write_text(mxfile, encoding="utf-8")
    embedded = out.copy()
    embedded[0] = embedded[0].replace("<svg ", f'<svg content="{escape(mxfile)}" ', 1)
    drawio_svg.write_text("\n".join(embedded), encoding="utf-8")
    print(f"wrote {svg.name}, {drawio.name} ({sum(1 for c in CELLS if c)} shapes), {drawio_svg.name}")
