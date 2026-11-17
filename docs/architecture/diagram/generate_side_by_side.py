#!/usr/bin/env python3
"""Put the three isolation-tier diagrams (ADR 0014) next to each other in one wide image.

    python3 docs/architecture/diagram/generate_side_by_side.py
    NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs tiers-side-by-side

Reads solution-architecture.svg (Tier 1), tier2-shared-cell.svg and tier3-pooled.svg, so run it after
generate.py and generate_tiers.py. Each diagram is copied in as-is, scaled to the same width, under a
header with the tier's one-line summary, cost, data allowed and blast radius. Writes
tiers-side-by-side.svg and, with the second command, tiers-side-by-side.png. There is no .drawio
version: edit the three source diagrams instead.

The facts in the headers come from docs/architecture/isolation-tiers.md; keep the two in step.
"""
import re
from html import escape
from pathlib import Path

from drawlib import C, FONT

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

COL, GAP, M = 2500, 80, 60          # column width, gap between columns, outer margin
CARD_Y, CARD_H = 290, 300           # header card per tier
DIAG_Y = CARD_Y + CARD_H + 40       # top of the diagrams
W = 2 * M + 3 * COL + 2 * GAP


def text(x, y, s, size, weight=400, fill=None, anchor="start"):
    return (f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill or C["ink"]}" text-anchor="{anchor}">{escape(s)}</text>')


def embed(name, prefix, x, y):
    """The diagram's SVG as a nested <svg> scaled to COL wide, with its ids prefixed so markers can't collide."""
    src = (HERE / f"{name}.svg").read_text(encoding="utf-8")
    w, h = map(int, re.search(r'<svg[^>]* width="(\d+)" height="(\d+)"', src).groups())
    body = src[src.index(">", src.index("<svg")) + 1: src.rindex("</svg>")]
    body = re.sub(r'id="([^"]+)"', rf'id="{prefix}-\1"', body)
    body = re.sub(r'url\(#([^)]+)\)', rf'url(#{prefix}-\1)', body)
    body = re.sub(r'href="#([^"]+)"', rf'href="#{prefix}-\1"', body)
    scaled_h = round(h * COL / w)
    return (f'<svg x="{x}" y="{y}" width="{COL}" height="{scaled_h}" viewBox="0 0 {w} {h}">{body}</svg>'
            f'<rect x="{x}" y="{y}" width="{COL}" height="{scaled_h}" fill="none" stroke="{C["chip_stroke"]}" '
            f'stroke-width="3"/>'), scaled_h


def main():
    parts, bottom = [], 0
    for i, t in enumerate(TIERS):
        x = M + i * (COL + GAP)
        parts.append(f'<rect x="{x}" y="{CARD_Y}" width="{COL}" height="{CARD_H}" rx="18" fill="#f7f8fa" '
                     f'stroke="#7a8594" stroke-width="3"/>')
        parts.append(text(x + 40, CARD_Y + 82, t["title"], 60, 700))
        parts.append(text(x + 40, CARD_Y + 140, t["caption"], 36, 600))
        parts.append(text(x + 40, CARD_Y + 200, t["facts"][0], 32, 400, C["ink"]))
        parts.append(text(x + 40, CARD_Y + 250, t["facts"][1], 32, 400, C["muted"]))
        svg, h = embed(t["file"], f"t{i + 1}", x, DIAG_Y)
        parts.append(svg)
        bottom = max(bottom, DIAG_Y + h)

    H = bottom + 110
    H += H % 2                       # the file declares half size, so keep it even
    head = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W // 2}" height="{H // 2}" viewBox="0 0 {W} {H}">',
        "<defs>",
        f'<marker id="spectrum" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" '
        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{C["muted"]}"/></marker>',
        "</defs>",
        f'<rect width="100%" height="100%" fill="{C["bg"]}"/>',
        text(M, 110, "Three isolation tiers, side by side (ADR 0014)", 72, 700),
        text(M, 172, "Read left to right: each tier shares more of the expensive, stateless parts (front door, "
                     "AI gateway, compute, search units) and keeps the cheap parts that hold data per client. "
                     "Azure OpenAI tokens cost the same in every tier.", 34, 400, C["muted"]),
        f'<line x1="{M + 10}" y1="248" x2="{W - M - 10}" y2="248" stroke="{C["muted"]}" stroke-width="4" '
        f'marker-start="url(#spectrum)" marker-end="url(#spectrum)"/>',
        text(M + 60, 234, "More isolated, more expensive", 30, 600, C["muted"]),
        text(W - M - 60, 234, "More shared, cheaper", 30, 600, C["muted"], "end"),
    ]
    foot = [
        text(M, H - 50, "Fixed costs are approximate US list prices (USD/month), with Standard v2 API Management, to "
                        "show the shape of the saving. Details, cost math and the trade-offs of each tier: "
                        "docs/architecture/isolation-tiers.md. Generated by generate_side_by_side.py from the three "
                        "tier diagrams.", 28, 400, C["muted"]),
        "</svg>",
    ]
    out = HERE / "tiers-side-by-side.svg"
    out.write_text("\n".join(head + parts + foot), encoding="utf-8")
    print(f"wrote {out.name} ({W}x{H})")


if __name__ == "__main__":
    main()
