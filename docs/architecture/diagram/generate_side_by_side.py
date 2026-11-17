#!/usr/bin/env python3
"""Put the three isolation-tier diagrams (ADR 0014) next to each other in one wide diagram.

    python3 docs/architecture/diagram/generate_side_by_side.py
    NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs tiers-side-by-side

Reads Tier 1 (solution-architecture), tier2-shared-cell and tier3-pooled, each as .svg and .drawio, so run
it after generate.py and generate_tiers.py. Each diagram is copied in unchanged, at its own size, under a
header with the tier's one-line summary, cost, data allowed, blast radius and boundary. Writes
tiers-side-by-side.svg, .drawio (one draw.io page, each tier on its own layer, every shape editable) and
.drawio.svg and, with the second command, tiers-side-by-side.png.

The facts in the headers come from docs/architecture/isolation-tiers.md; keep the two in step.
"""
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from drawlib import C, CELLS, out, arrow, open_canvas, rect, save, text

HERE = Path(__file__).parent

TIERS = [
    {
        "file": "solution-architecture",
        "title": "Tier 1: Dedicated (default)",
        "caption": "A private copy of everything, in the client's own subscription",
        "facts": [
            "~USD 1,500 per client a month  ·  up to highly confidential data  ·  blast radius: 1 client",
            "Boundary: the client's own subscription. Shared: only P&T's hub. Terraform: stamps/client",
        ],
    },
    {
        "file": "tier2-shared-cell",
        "title": "Tier 2: Shared cell",
        "caption": "Shared front door, compute and AI gateway; data, keys and models stay per client",
        "facts": [
            "~USD 170 per client a month at 20 per cell  ·  up to confidential data  ·  blast radius: 20 clients",
            "Boundary: own resource group, keys off, roles only for the client's identities. Terraform: stamps/cell",
        ],
    },
    {
        "file": "tier3-pooled",
        "title": "Tier 3: Pooled",
        "caption": "One app for many tenants; Azure checks the signed-in user's own token on every data call",
        "facts": [
            "~USD 45 per tenant a month at 45 per pool  ·  public and internal data only  ·  blast radius: 45 tenants",
            "Boundary: the user's token; the app itself has no data role. Terraform: stamps/pool",
        ],
    },
]

GAP, M = 80, 60                     # gap between columns, outer margin
CARD_Y, CARD_H = 290, 300           # header card per tier
DIAG_Y = CARD_Y + CARD_H + 40       # top of the diagrams


def size(name):
    src = (HERE / f"{name}.svg").read_text(encoding="utf-8")
    return tuple(map(int, re.search(r'<svg[^>]* width="(\d+)" height="(\d+)"', src).groups()))


def embed_svg(name, prefix, x, y, w, h):
    """The diagram's SVG as a nested <svg>, with its ids prefixed so arrow markers can't collide."""
    src = (HERE / f"{name}.svg").read_text(encoding="utf-8")
    body = src[src.index(">", src.index("<svg")) + 1: src.rindex("</svg>")]
    body = re.sub(r'id="([^"]+)"', rf'id="{prefix}-\1"', body)
    body = re.sub(r'url\(#([^)]+)\)', rf'url(#{prefix}-\1)', body)
    body = re.sub(r'href="#([^"]+)"', rf'href="#{prefix}-\1"', body)
    out.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>')


def embed_drawio(name, prefix, layer, dx, dy):
    """The diagram's draw.io cells on a layer of their own, moved by (dx, dy), with ids prefixed."""
    root = ET.parse(HERE / f"{name}.drawio").getroot().find("diagram/mxGraphModel/root")
    CELLS.append(f'<mxCell id="{prefix}" value="{layer}" parent="0"/>')
    for cell in root:
        if cell.get("id") in ("0", "1"):
            continue
        cell.set("id", f"{prefix}-{cell.get('id')}")
        cell.set("parent", prefix if cell.get("parent") == "1" else f"{prefix}-{cell.get('parent')}")
        geo = cell.find("mxGeometry")
        if geo is not None and geo.get("relative") != "1":
            geo.set("x", str(float(geo.get("x", 0)) + dx))
            geo.set("y", str(float(geo.get("y", 0)) + dy))
        for pt in cell.iter("mxPoint"):     # edges are drawn from absolute points (no source/target cells)
            pt.set("x", str(float(pt.get("x", 0)) + dx))
            pt.set("y", str(float(pt.get("y", 0)) + dy))
        CELLS.append(ET.tostring(cell, encoding="unicode"))


def main():
    sizes = [size(t["file"]) for t in TIERS]
    xs = [M]
    for w, _ in sizes[:-1]:
        xs.append(xs[-1] + w + GAP)
    W = xs[-1] + sizes[-1][0] + M
    H = DIAG_Y + max(h for _, h in sizes) + 110
    H += H % 2                       # the .svg declares half size (see below), so keep it even

    open_canvas(W, H)
    text(M, 110, "Three isolation tiers, side by side (ADR 0014)", 72, 700)
    text(M, 172, "Read left to right: each tier shares more of the expensive, stateless parts (front door, "
                 "AI gateway, compute, search units) and keeps the cheap parts that hold data per client. "
                 "Azure OpenAI tokens cost the same in every tier.", 34, 400, fill=C["muted"])
    arrow([(W // 2, 248), (M + 10, 248)], C["line"], sw=4)
    arrow([(W // 2, 248), (W - M - 10, 248)], C["line"], sw=4)
    text(M + 60, 234, "More isolated, more expensive", 30, 600, fill=C["muted"])
    text(W - M - 60, 234, "More shared, cheaper", 30, 600, "end", C["muted"])

    for i, (t, x, (w, h)) in enumerate(zip(TIERS, xs, sizes), start=1):
        rect(x, CARD_Y, w, CARD_H, "#f7f8fa", "#7a8594", rx=18, sw=3)
        text(x + 40, CARD_Y + 82, t["title"], 60, 700)
        text(x + 40, CARD_Y + 140, t["caption"], 36, 600)
        text(x + 40, CARD_Y + 200, t["facts"][0], 32, 400)
        text(x + 40, CARD_Y + 250, t["facts"][1], 32, 400, fill=C["muted"])
        embed_svg(t["file"], f"t{i}", x, DIAG_Y, w, h)
        embed_drawio(t["file"], f"t{i}", t["title"], x, DIAG_Y)
        rect(x, DIAG_Y, w, h, "none", C["chip_stroke"], rx=0, sw=3)

    text(M, H - 50, "Fixed costs are approximate US list prices (USD/month), with Standard v2 API Management, to "
                    "show the shape of the saving. Details, cost math and the trade-offs of each tier: "
                    "docs/architecture/isolation-tiers.md. Generated by generate_side_by_side.py from the three "
                    "tier diagrams.", 28, 400, fill=C["muted"])
    save(HERE / "tiers-side-by-side", W, H, "tiers-side-by-side", "Three isolation tiers side by side")

    # The .svg declares half its viewBox size, so render-png.mjs (2x) writes a PNG at the native size
    # instead of one too large to open comfortably.
    svg = HERE / "tiers-side-by-side.svg"
    svg.write_text(svg.read_text(encoding="utf-8").replace(
        f'width="{W}" height="{H}"', f'width="{W // 2}" height="{H // 2}"', 1), encoding="utf-8")
    print(f"canvas {W}x{H}")


if __name__ == "__main__":
    main()
