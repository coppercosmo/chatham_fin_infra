#!/usr/bin/env python3
"""Generate the isolation-tier diagrams (ADR 0014) in the same style as the main architecture diagram.

    python3 docs/architecture/diagram/generate_tiers.py
    NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs tier2-shared-cell tier3-pooled

Writes, for each tier, <name>.svg, <name>.drawio (editable in app.diagrams.net with Azure icons),
<name>.drawio.svg and, with the second command, <name>.png. Tier 1 (dedicated subscription per client)
is the main diagram, solution-architecture.svg.

Everything drawn maps to Terraform in this repo: terraform/stamps/cell + terraform/stamps/cell-client
(Tier 2) and terraform/stamps/pool (Tier 3).
"""
from pathlib import Path

from drawlib import *  # noqa: F401,F403
from drawlib import ICONS, reset, open_canvas, save

HERE = Path(__file__).parent

# Two extra fills for the tier diagrams. Ownership colours (P&T blue, per-client amber) keep their meaning.
C.update({
    "sub_fill": "#f7f8fa", "sub_stroke": "#7a8594",        # a subscription boundary
    "shared_fill": "#e6f4f6", "shared_stroke": "#1f7f8c",  # shared: carries client traffic, stores no client data
})
# More specific icon matches first (first match wins).
ICONS[:0] = [
    ("ca-advisor", "other/Worker_Container_App"), ("job-", "other/Worker_Container_App"),
    ("ca-", "other/Worker_Container_App"), ("App registration", "identity/App_Registrations"),
    ("Budget", "general/Cost_Management"), ("Redis", "databases/Cache_Redis"),
    ("Encryption scopes", "security/Key_Vaults"), ("rg-", "general/Resource_Groups"),
]


def stack(x, y, w, items, gap=10, **kw):
    """Chips one under another; returns (positions, bottom)."""
    pos = {}
    for key, title, sub, extra in items:
        h = chip(x, y, w, None, title, sub, **{**kw, **extra})
        pos[key] = (x, y, w, h)
        y += h + gap
    return pos, y


def mid_left(p):
    return (p[0], p[1] + p[3] // 2)


def mid_right(p):
    return (p[0] + p[2], p[1] + p[3] // 2)


def legend(y, w, kinds, flows, note):
    h = 70 + 28 * ((len(flows) + 1) // 2) + 30
    section(30, y, w - 60, h, "Legend", "ext")
    lx = 50
    for kind, label in kinds:
        rect(lx, y + 48, 34, 22, C[f"{kind}_fill"], C[f"{kind}_stroke"], rx=4, sw=2)
        text(lx + 44, y + 64, label, 13)
        lx += 44 + len(label) * 7 + 30
    rect(lx, y + 48, 34, 22, "#ffffff", C["sec"], rx=4, sw=2)
    text(lx + 44, y + 64, "Key isolation control", 13)
    for k, (n, col, label) in enumerate(flows):
        fx = 50 + (k % 2) * ((w - 100) // 2)
        fy = y + 84 + (k // 2) * 28
        badge(fx + 12, fy + 9, n, col)
        text(fx + 30, fy + 14, label, 12)
    text(50, y + h - 14, note, 12, fill=C["muted"])
    return y + h


def notes_band(y, w, boxes):
    """A row of titled text boxes; returns the bottom."""
    bw = (w - 60 - 15 * (len(boxes) - 1)) // len(boxes)
    hs = [chip_h(bw, t, s, 14, 12) for t, s, _ in boxes]
    h = max(hs)
    for i, (t, s, kw) in enumerate(boxes):
        chip(30 + i * (bw + 15), y, bw, h, t, s, title_size=14, sub_size=12, **kw)
    return y + h


# ================================================================= Tier 2: shared cell
def tier2():
    reset()
    W = 2500
    open_canvas(W)
    text(30, 46, "Tier 2: shared cell. Shared front door, compute and AI gateway; every client keeps its own data, "
         "keys, models and identities", 26, 700)
    text(30, 72, "ADR 0014. One subscription (a 'cell') holds up to 20 clients. What's shared processes client traffic "
         "but stores none of it; everything that stores client data is per client and only that client's identities "
         "can use it.", 15, fill=C["muted"])
    top = 105
    main_h = 980

    # ---------------------------------------------------------------- users
    ux, uw = 30, 330
    section(ux, top, uw, main_h, "Client users", "ext")
    U, ub = stack(ux + 15, top + 60, uw - 30, [
        ("nw", "northwind analysts: ExpressRoute or VPN",
         ["through P&T's hub; firewall admits", "northwind's ranges to the cell App", "Gateway IP:443",
          "northwind.ai.<domain>"], {}),
        ("ts", "tailspin analysts (on Azure): Private Link",
         ["private endpoint in tailspin's OWN", "subscription -> cell App Gateway", "Private Link frontend"], {}),
        ("lw", "litware analysts: internet",
         ["public frontend, litware's egress", "IPs only (per-site WAF allow-list)"], {}),
    ], gap=14)
    text(ux + 15, ub + 26, "Sign-in", 14, 700)
    lines(ux + 15, ub + 48, [
        "Each client app trusts only its own",
        "client's users (their Entra tenant or",
        "a B2B group). A user who reaches",
        "another client's host name gets a",
        "sign-in they can't pass.",
    ], 12, fill=C["muted"])
    text(ux + 15, ub + 150, "Network separation is coarser", 14, 700)
    lines(ux + 15, ub + 172, [
        "All clients share one frontend IP, so",
        "the hub firewall and Private Link can't",
        "tell clients apart by address. The host",
        "name, per-site WAF rules and sign-in",
        "do. Clients that need network-level",
        "separation stay on Tier 1.",
    ], 12, fill=C["muted"])

    # ---------------------------------------------------------------- hub
    hx, hw = 380, 290
    section(hx, top, hw, main_h, "P&T hub (shared)", "pt", "unchanged from Tier 1 (ADR 0013)")
    HB, _ = stack(hx + 15, top + 70, hw - 30, [
        ("dns", "DNS (P&T)", ["<client>.ai.<domain> -> the cell", "App Gateway private IP"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("pl", "privatelink.* Private DNS zones", ["records for each client's private", "endpoints, written by DINE policy"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("pol", "Azure Policy (AI Advisory MG)", ["same guardrail initiative as Tier 1", "(modules/policy-guardrails)"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"], "sec": True}),
        ("ent", "Entra ID groups + PIM", ["per-client readers / operators", "groups, scoped to the client RG"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("fw", "Azure Firewall", ["one rule per routed client:", "its ranges -> cell AGW IP:443", "default deny; egress inspected"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
    ], gap=14)

    # ---------------------------------------------------------------- cell subscription
    cx = hx + hw + 45
    cw = W - 30 - cx
    section(cx, top, cw, main_h, "sub: aiadv-cell-eus2-01   (terraform/stamps/cell + one terraform/stamps/cell-client per client)",
            "sub", "Vended once by P&T into the AI Advisory / Clients MG. A full cell gets a sibling: aiadv-cell-eus2-02.")

    # shared resource group
    sx, sy, sw = cx + 15, top + 62, 1010
    section(sx, sy, sw, main_h - 77, "rg-cell01-prd-eus2   (shared: carries client traffic, stores no client data)", "shared")
    vx, vy, vw = sx + 15, sy + 45, sw - 30
    rect(vx, vy, vw, 690, C["vnet_fill"], C["vnet_stroke"], rx=10, sw=1.5)
    text(vx + 12, vy + 22, "vnet-cell01-prd-eus2 (10.110.0.0/22), peered to the hub; 0.0.0.0/0 -> hub firewall", 13, 600,
         fill=C["vnet_stroke"])

    half = (vw - 45) // 2
    # snet-agw
    ax, ay = vx + 15, vy + 36
    rect(ax, ay, half, 190, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, ay + 18, "snet-agw /24", 12, 600, fill=C["muted"])
    agw_h = chip(ax + 10, ay + 28, half - 20, None, "App Gateway WAF_v2 (shared, multi-site)", [
        "one listener, TLS certificate and WAF policy per client",
        "host name picks the client's backend; require SNI",
        "per-site WAF: client IP allow-list + rate limit",
        "Private Link frontend for clients on Azure",
        "access + WAF logs to the cell workspace, no bodies",
    ], sec=True)
    AGW = (ax + 10, ay + 28, half - 20, agw_h)
    # snet-apim
    mx_ = ax + half + 15
    rect(mx_, ay, half, 190, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(mx_ + 10, ay + 18, "snet-apim /26", 12, 600, fill=C["muted"])
    apim_h = chip(mx_ + 10, ay + 28, half - 20, None, "AI gateway (API Management, internal, shared)", [
        "one API per client: /northwind/openai, /tailspin/...",
        "accepts only that client's id-<client>-app token",
        "calls that client's Azure OpenAI as id-<client>-gw",
        "token limit + token metric per client (showback)",
        "prompt and response bodies never logged",
    ], sec=True)
    APIM = (mx_ + 10, ay + 28, half - 20, apim_h)

    # snet-apps
    py = ay + 205
    rect(ax, py, vw - 30, 225, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, py + 18, "snet-apps /24", 12, 600, fill=C["muted"])
    envw = 215
    chip(ax + 10, py + 28, envw, 180, "Container Apps environment (internal, shared)",
         ["workload profiles", "one container app per", "client, each with its own", "user-assigned identity;",
          "same image digest,", "client set by CLIENT_CODE"])
    appw = (vw - 50 - envw - 45) // 3
    APPS = {}
    for i, (code, extra) in enumerate([("northwind", "min 1 replica"), ("tailspin", "scale to zero"),
                                       ("litware", "dedicated profile")]):
        h = chip(ax + 25 + envw + i * (appw + 15), py + 28, appw, 180, f"ca-{code}", [
            f"runs as id-{code}-app (no secrets)",
            "ingress allows snet-agw only, so",
            "apps can't call each other",
            extra,
        ], fill=C["cli_fill"], stroke=C["cli_stroke"])
        APPS[code] = (ax + 25 + envw + i * (appw + 15), py + 28, appw, h)

    # snet-pe
    ey = py + 240
    rect(ax, ey, vw - 30, 190, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, ey + 18, "snet-pe /26", 12, 600, fill=C["muted"])
    PES = {}
    pe_items = [
        ("pe-search, pe-kv (cell)", ["-> shared AI Search and", "the cell's certificate vault"], {}, envw),
        ("pe-northwind-oai / -kv / -blob", ["-> northwind's AOAI, vault,", "storage only"], {"fill": C["cli_fill"], "stroke": C["cli_stroke"]}, appw),
        ("pe-tailspin-oai / -kv / -blob", ["-> tailspin's AOAI, vault,", "storage only"], {"fill": C["cli_fill"], "stroke": C["cli_stroke"]}, appw),
        ("pe-litware-oai / -kv / -blob", ["-> litware's AOAI, vault,", "storage only"], {"fill": C["cli_fill"], "stroke": C["cli_stroke"]}, appw),
    ]
    pxx = ax + 10
    for i, (t, s, kw, w_) in enumerate(pe_items):
        h = chip(pxx, ey + 30, w_, 78, t, s, **kw)
        PES[i] = (pxx, ey + 30, w_, h)
        pxx += w_ + 15
    text(ax + 10, ey + 158, "Each client's endpoints point only at that client's resources. Reaching an endpoint's IP is not access:",
         12, fill=C["sec"])
    text(ax + 10, ey + 176, "keys are off everywhere, and only Entra tokens for the client's own identities are accepted.",
         12, fill=C["sec"])

    # shared services outside the VNet
    oy = vy + 705
    ow = (sw - 30 - 30) // 3
    SH = {}
    for i, (key, t, s, kw) in enumerate([
        ("srch", "Azure AI Search (shared, S1, 2 replicas)",
         ["one index per client, push only", "index-scoped RBAC: each app can", "read/write only its own index",
          "no indexers (they bypass index RBAC)"], {"sec": True}),
        ("kv", "Key Vault (cell)", ["TLS certificates for client host", "names only; read by id-cell-agw", "no client secrets here"], {}),
        ("law", "Log Analytics (cell)", ["App Gateway, WAF, APIM and", "environment logs; no prompt bodies;",
                                         "platform ops group only"], {}),
    ]):
        h = chip(sx + 15 + i * (ow + 15), oy, ow, None, t, s, **kw)
        SH[key] = (sx + 15 + i * (ow + 15), oy, ow, h)
    text(sx + 15, oy + max(p[3] for p in SH.values()) + 26,
         "Deployed by id-deploy-cell01 (shared RG + per-client wiring). It holds no role on any client's data.",
         12, fill=C["muted"])

    # per-client resource groups
    rx, rw = cx + 15 + sw + 15, cw - sw - 45
    ry = top + 62
    CL = {}
    for code, full in [("northwind", True), ("tailspin", False), ("litware", False)]:
        slot_ = slot()
        text(rx + 14, ry + 26, f"rg-{code}-prd-eus2", 17, 700, fill=C["cli_stroke"])
        text(rx + 14, ry + 45, "per client: client data, keys, models; deployed by id-deploy-" + code, 12, fill=C["muted"])
        iy = ry + 58
        cw2 = (rw - 45) // 2
        if full:
            items = [
                ("oai", "Azure OpenAI (northwind's own account)", ["DataZoneStandard; capacity carved", "from the cell's regional quota", "trusts only id-northwind-gw"], {"sec": True}),
                ("id", "id-northwind-app, id-northwind-gw", ["app: storage, vault, own index", "gw: OpenAI User on own AOAI"], {"sec": True}),
                ("st", "Storage", ["documents; shared keys off", "only id-northwind-app"], {}),
                ("law", "Log Analytics + App Insights", ["app telemetry and data-plane", "logs for northwind only"], {}),
                ("kv", "Key Vault", ["client secrets; CMK key", "for storage + AOAI (option)"], {}),
                ("bud", "Budget (resource group scope)", ["plus showback of shared costs", "from APIM token metrics"], {}),
            ]
            col_y = [iy, iy]
            for k, (key, t, s, kw) in enumerate(items):
                c = k % 2
                h = chip(rx + 15 + c * (cw2 + 15), col_y[c], cw2, None, t, s, fill="#ffffff", **kw)
                CL[(code, key)] = (rx + 15 + c * (cw2 + 15), col_y[c], cw2, h)
                col_y[c] += h + 10
            iy = max(col_y)
        else:
            for key, t, s in [("oai", "Azure OpenAI · Storage · Key Vault · Log Analytics",
                               [f"same shape as northwind; only {code}'s identities have roles"]),
                              ("id", f"id-{code}-app, id-{code}-gw, budget", [])]:
                h = chip(rx + 15, iy, rw - 30, None, t, s)
                CL[(code, key)] = (rx + 15, iy, rw - 30, h)
                iy += h + 10
        rect(rx, ry, rw, iy - ry + 6, C["cli_fill"], C["cli_stroke"], rx=12, sw=2, at=slot_)
        ry = iy + 22
    text(rx + 5, ry + 6, "Adding a client = a new client RG + one entry", 13, 600)
    text(rx + 5, ry + 24, "in the cell's clients map. No vending, no new", 13, 600)
    text(rx + 5, ry + 42, "gateway, no new environment.", 13, 600)

    # ---------------------------------------------------------------- flows
    lane1, lane5 = hx + hw + 14, hx + hw + 30  # vertical lanes in the gap between the hub and the cell
    fw = HB["fw"]
    # 1 routed user -> hub firewall -> App Gateway
    nwy = mid_right(U["nw"])
    fwl = mid_left(fw)
    arrow([nwy, (ux + uw + 10, nwy[1]), (ux + uw + 10, fwl[1]), fwl], C["flow_user"])
    fwr = (fw[0] + fw[2], fw[1] + 22)
    agw_in = (AGW[0], AGW[1] + 34)
    arrow([fwr, (lane1, fwr[1]), (lane1, agw_in[1]), agw_in], C["flow_user"])
    badge(lane1, fwr[1] - 40, 1, C["flow_user"])
    # 5 Private Link (tailspin): over the top of the hub column, never through its boxes
    tsy = mid_right(U["ts"])
    hub_lane = top + 56
    arrow([tsy, (ux + uw + 4, tsy[1]), (ux + uw + 4, hub_lane), (lane5, hub_lane), (lane5, AGW[1] + 74), (AGW[0], AGW[1] + 74)],
          C["flow_user"], dash="3 4")
    badge(lane5, hub_lane + 40, 5, C["flow_user"])
    # App Gateway -> ca-northwind
    a0 = APPS["northwind"]
    down_x = a0[0] + 40
    arrow([(down_x, AGW[1] + AGW[3]), (down_x, a0[1])], C["flow_user"])
    # 2 app -> APIM -> client's own AOAI
    gap_y = py - 7
    up_x = a0[0] + a0[2] - 30
    arrow([(up_x, a0[1]), (up_x, gap_y), (APIM[0] + 40, gap_y), (APIM[0] + 40, APIM[1] + APIM[3])], C["flow_model"], sw=2.6)
    badge(up_x, gap_y + 30, 2, C["flow_model"])
    oai = CL[("northwind", "oai")]
    m_lane = sx + sw - 7
    arrow([mid_right(APIM), (m_lane, mid_right(APIM)[1]), (m_lane, oai[1] + 26), (oai[0], oai[1] + 26)], C["flow_model"], sw=2.6)
    # 3 app identity -> its own storage (through its own private endpoint)
    st = CL[("northwind", "st")]
    pe1 = PES[1]
    arrow([(down_x, a0[1] + a0[3]), (down_x, pe1[1])], C["flow_mgmt"], sw=2.2)
    badge(down_x, a0[1] + a0[3] + 16, 3, C["flow_mgmt"])
    d_lane_y = pe1[1] + pe1[3] + 20
    d_lane_x = sx + sw + 7
    arrow([(pe1[0] + pe1[2] - 30, pe1[1] + pe1[3]), (pe1[0] + pe1[2] - 30, d_lane_y), (d_lane_x, d_lane_y),
           (d_lane_x, st[1] + st[3] // 2), (st[0], st[1] + st[3] // 2)], C["flow_mgmt"], sw=2.2)
    # 4 egress: VNet -> hub firewall
    eg_y = fw[1] + fw[3] - 14
    arrow([(vx, eg_y), (fw[0] + fw[2], eg_y)], C["flow_egress"], dash="6 4", sw=1.8)
    badge(vx - 30, eg_y, 4, C["flow_egress"])

    # ---------------------------------------------------------------- notes
    by = top + main_h + 25
    bottom = notes_band(by, W, [
        ("How clients stay apart in a shared cell", [
            "1. Data, keys and models are separate Azure resources per client, in the client's own resource group.",
            "2. Each client has its own identities. Only id-<client>-app can use the client's storage, vault and index;",
            "    only id-<client>-gw can call the client's Azure OpenAI. Keys are off everywhere, so a token is the only way in.",
            "3. The gateway API for a client accepts only that client's app token and calls out only as that client's gateway identity.",
            "4. Container apps accept traffic only from the App Gateway subnet, so one client's app can't call another's.",
            "5. Per-client deployment identity: Contributor on its own resource group only. The cell identity has no data roles.",
            "6. Terraform tests assert 1 to 5 for every client in the cell's clients map.",
        ], {"sec": True}),
        ("What it costs (approx. list price, USD/month)", [
            "Shared per cell: App Gateway WAF_v2 ~400, APIM ~700 (Standard v2*), AI Search S1 x2 ~490,",
            "Container Apps environment ~0 idle, cell Log Analytics ~50. About 1,650 per cell.",
            "Per client: 3 private endpoints ~22, logs ~25, an always-on replica ~40, tokens as used.",
            "About 90 per client + 1,650 / clients in the cell. At 20 clients: ~170 per client.",
            "*Premium APIM (internal VNet mode, as built today) is ~2,800: ~280 per client at 20.",
            "Tier 1 is ~700 to ~1,400 per client before tokens (~3,500 with a Premium gateway).",
        ], {}),
        ("Fits / doesn't fit", [
            "Fits: confidential client data where the contract accepts shared, Microsoft-managed",
            "compute and edge, but wants dedicated data stores, keys, models and logs. Most hosted",
            "solutions. Onboarding in hours, not days: no vending, no new gateway.",
            "Doesn't fit: contracts that require a dedicated subscription, network-level separation,",
            "their own ExpressRoute path with per-client firewall rules, or PTU capacity of their own.",
            "Those clients stay on Tier 1. Moving up is a data copy plus a new stamp.",
        ], {}),
    ])
    H = legend(bottom + 20, W, [("pt", "Owned by Platform Engineering (P&T)"),
                                 ("shared", "Shared in the cell: carries client traffic, stores none"),
                                 ("cli", "Per client: client data, keys, models, identities"),
                                 ("ext", "Users")],
               [(1, C["flow_user"], "User path: client network -> hub firewall -> shared App Gateway (listener per client) -> client's app"),
                (2, C["flow_model"], "Model path: client's app -> shared AI gateway (client's API) -> client's own Azure OpenAI"),
                (3, C["flow_mgmt"], "Data path: client's app identity -> its own storage, vault and search index (private endpoints)"),
                (4, C["flow_egress"], "Egress: cell workload subnets -> hub firewall (UDR)"),
                (5, C["flow_user"], "Private Link: client's own Azure VNet -> private endpoint -> cell App Gateway Private Link")],
               "Sources: docs/adr/0014-isolation-tiers.md, docs/architecture/isolation-tiers.md, terraform/stamps/cell, "
               "terraform/stamps/cell-client. Names and addresses are the example configs.") + 20
    save(HERE / "tier2-shared-cell", W, H, "tier2-shared-cell", "Tier 2: shared cell")


# ================================================================= Tier 3: pooled
def tier3():
    reset()
    W = 2500
    open_canvas(W)
    text(30, 46, "Tier 3: pooled. One multi-tenant app for many clients; Azure enforces each client's data partition "
         "on the signed-in user's own token", 26, 700)
    text(30, 72, "ADR 0014. For low-sensitivity and standard-content solutions, trials and internal tools. Shared compute, "
         "stores and model deployments; per-client containers, indexes, encryption scopes, groups and token limits.",
         15, fill=C["muted"])
    top = 105
    main_h = 870

    # ---------------------------------------------------------------- users + Entra
    ux, uw = 30, 360
    section(ux, top, uw, main_h, "Client users and identity", "ext")
    U, ub = stack(ux + 15, top + 60, uw - 30, [
        ("c1", "contoso users (own Entra tenant)", ["sign in to the multi-tenant app", "registration; tid = contoso"], {}),
        ("c2", "adatum users (B2B guests)", ["guests in Chatham's tenant,", "in group sg-aiadv-adatum-users"], {}),
        ("c3", "proseware users", ["same pattern"], {}),
    ], gap=12)
    E, eb = stack(ux + 15, ub + 10, uw - 30, [
        ("app", "App registration: AI Advisory pooled app (P&T)",
         ["app roles Tenant.contoso, Tenant.adatum ...", "each client's group is assigned only its", "own role; the role arrives in the token",
          "exposes an API scope for on-behalf-of"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"], "sec": True}),
        ("grp", "Entra ID groups (P&T)", ["sg-aiadv-<tenant>-users per client:", "the group IS the data permission"],
         {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
    ], gap=12)
    text(ux + 15, eb + 20, "The tenant is never taken from a header,", 12, 600)
    text(ux + 15, eb + 38, "URL or request body: only from a signed", 12, 600)
    text(ux + 15, eb + 56, "token claim.", 12, 600)

    # ---------------------------------------------------------------- hub (narrow)
    hx, hw = 410, 260
    section(hx, top, hw, main_h, "P&T hub (shared)", "pt")
    HB, hb_bottom = stack(hx + 15, top + 60, hw - 30, [
        ("fw", "Azure Firewall", ["egress allow-list for the pool", "routed users -> pool AGW:443"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("dns", "DNS (P&T)", ["advisor.ai.<domain> -> pool", "App Gateway (one host name)"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("pl", "privatelink.* Private DNS zones", ["records for the pool's private", "endpoints (DINE policy)"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
        ("pol", "Azure Policy", ["same guardrail initiative"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"], "sec": True}),
    ], gap=14)

    # ---------------------------------------------------------------- pool subscription
    px = hx + hw + 45
    pw = W - 30 - px
    section(px, top, pw, main_h, "sub: aiadv-pool-eus2-01   (terraform/stamps/pool: one state; tenants are entries in a map)", "sub",
            "Every resource here is shared. Per-tenant pieces are sub-resources (containers, indexes, encryption scopes) "
            "or role assignments and limits, all created from the tenants map.")
    vx, vy, vw = px + 15, top + 62, 1060
    rect(vx, vy, vw, 560, C["vnet_fill"], C["vnet_stroke"], rx=10, sw=1.5)
    text(vx + 12, vy + 22, "vnet-pool01-prd-eus2 (10.120.0.0/22), peered to the hub; 0.0.0.0/0 -> hub firewall", 13, 600, fill=C["vnet_stroke"])
    half = (vw - 45) // 2
    ax, ay = vx + 15, vy + 36
    rect(ax, ay, half, 150, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, ay + 18, "snet-agw", 12, 600, fill=C["muted"])
    h = chip(ax + 10, ay + 28, half - 20, None, "App Gateway WAF_v2 (pool)", [
        "one listener: advisor.ai.<domain>", "WAF policy + rate limit per client IP", "no per-client certificates or listeners"],
        fill=C["shared_fill"], stroke=C["shared_stroke"])
    AGW = (ax + 10, ay + 28, half - 20, h)
    mx_ = ax + half + 15
    rect(mx_, ay, half, 150, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(mx_ + 10, ay + 18, "snet-apim", 12, 600, fill=C["muted"])
    h = chip(mx_ + 10, ay + 28, half - 20, None, "AI gateway (APIM, internal, pool)", [
        "validates the signed-in user's token", "tenant = Tenant.<code> role claim", "token limit + metric per tenant",
        "calls the shared AOAI as its own identity"], sec=True)
    APIM = (mx_ + 10, ay + 28, half - 20, h)

    py = ay + 165
    rect(ax, py, vw - 30, 220, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, py + 18, "snet-apps: Container Apps environment (internal)", 12, 600, fill=C["muted"])
    h = chip(ax + 10, py + 28, (vw - 50) // 2, None, "ca-advisor (pooled, 2+ replicas)", [
        "one app, every tenant; resolves the tenant from the", "token's Tenant.<code> role, never from input",
        "reads data with the user's token (on-behalf-of), so", "Azure checks the user's group on every call",
        "caches keyed by tenant + user; no shared answer cache"], fill=C["shared_fill"], stroke=C["shared_stroke"], sec=True)
    APP = (ax + 10, py + 28, (vw - 50) // 2, h)
    jx = ax + 10 + (vw - 50) // 2 + 15
    h2 = chip(jx, py + 28, (vw - 50) // 2 - 15, None, "job-ingest-<tenant> (one per tenant)", [
        "background ingestion has no user, so each tenant's", "job runs as its own id-<tenant>-ingest identity",
        "with rights on that tenant's container and index only", "pay per execution: near-zero idle cost"],
        fill=C["cli_fill"], stroke=C["cli_stroke"], sec=True)
    JOB = (jx, py + 28, (vw - 50) // 2 - 15, h2)

    ey = py + 235
    rect(ax, ey, vw - 30, 110, C["subnet_fill"], C["subnet_stroke"], rx=6, dash="4 3")
    text(ax + 10, ey + 18, "snet-pe: private endpoints for the shared storage, search, AOAI and vault", 12, 600, fill=C["muted"])
    pew = (vw - 50 - 45) // 4
    for i, t in enumerate(["pe-blob", "pe-search", "pe-oai", "pe-kv"]):
        chip(ax + 10 + i * (pew + 15), ey + 32, pew, None, t, ["keys off, public off"])

    # data services (right of the VNet)
    dx, dw = vx + vw + 32, pw - vw - 62
    D, db = stack(dx, top + 62, dw, [
        ("st", "Storage (pool): one container per tenant", [
            "RBAC at CONTAINER scope: sg-aiadv-contoso-users and", "id-contoso-ingest on container contoso only",
            "encryption scope per tenant (CMK option: revoke the", "key to crypto-shred a tenant at offboarding)"],
         {"fill": C["shared_fill"], "stroke": C["shared_stroke"], "sec": True}),
        ("srch", "Azure AI Search (pool): one index per tenant", [
            "RBAC at INDEX scope for the tenant group + ingest id", "queries run with the user's token, push only",
            "(indexers would bypass index-level RBAC)"],
         {"fill": C["shared_fill"], "stroke": C["shared_stroke"], "sec": True}),
        ("oai", "Azure OpenAI (pool): shared deployments", [
            "stateless calls only: store=false, no Assistants,", "threads, files or stored completions",
            "per-tenant fairness enforced at the gateway"],
         {"fill": C["shared_fill"], "stroke": C["shared_stroke"]}),
        ("kv", "Key Vault (pool)", ["encryption-scope keys per tenant, TLS cert"],
         {"fill": C["shared_fill"], "stroke": C["shared_stroke"]}),
        ("law", "Log Analytics (pool)", ["every row carries the tenant; no prompt bodies;", "per-tenant export on request"],
         {"fill": C["shared_fill"], "stroke": C["shared_stroke"]}),
        ("tm", "Per-tenant config (tenants map)", ["container, index, encryption scope, group and", "ingest identity, token limit, monthly token quota"],
         {"fill": C["cli_fill"], "stroke": C["cli_stroke"]}),
    ], gap=12)

    # ---------------------------------------------------------------- flows
    lane_u, lane_e = hx + hw + 14, hx + hw + 30
    # 1 user -> pool App Gateway, under the hub's boxes rather than through them
    c1 = mid_right(U["c1"])
    below_hub = hb_bottom + 16
    agw_y = AGW[1] + AGW[3] // 2
    arrow([c1, (ux + uw + 10, c1[1]), (ux + uw + 10, below_hub), (lane_u, below_hub), (lane_u, agw_y), (AGW[0], agw_y)],
          C["flow_user"])
    badge(ux + uw + 10, below_hub - 40, 1, C["flow_user"])
    arrow([(AGW[0] + AGW[2] - 40, AGW[1] + AGW[3]), (AGW[0] + AGW[2] - 40, APP[1])], C["flow_user"])
    # 2 data with the user's own token (on-behalf-of) -> storage container / search index
    d_lane, m_lane, j_lane = vx + vw + 8, vx + vw + 16, vx + vw + 24
    low = py + 28 + max(APP[3], JOB[3]) + 14
    sty = D["st"][1] + 30
    sry = D["srch"][1] + 30
    arrow([(APP[0] + 40, APP[1] + APP[3]), (APP[0] + 40, low), (d_lane, low), (d_lane, sty), (dx, sty)], C["flow_mgmt"], sw=2.4)
    arrow([(d_lane, sry), (dx, sry)], C["flow_mgmt"], sw=2.4)
    badge(APP[0] + 40, low - 2, 2, C["flow_mgmt"])
    # 3 model via the gateway, still on the user's token
    gap_y = py - 7
    arrow([(APP[0] + APP[2] - 40, APP[1]), (APP[0] + APP[2] - 40, gap_y), (APIM[0] + 50, gap_y), (APIM[0] + 50, APIM[1] + APIM[3])],
          C["flow_model"], sw=2.6)
    badge(APP[0] + APP[2] - 40, gap_y + 28, 3, C["flow_model"])
    oy_ = D["oai"][1] + 30
    arrow([mid_right(APIM), (m_lane, mid_right(APIM)[1]), (m_lane, oy_), (dx, oy_)], C["flow_model"], sw=2.6)
    # 4 ingestion job with its own per-tenant identity
    jy = D["st"][1] + D["st"][3] - 16
    jx0 = (JOB[0] + JOB[2], JOB[1] + 30)
    arrow([jx0, (j_lane, jx0[1]), (j_lane, jy), (dx, jy)], C["flow_mgmt"], dash="6 4", sw=2)
    badge(JOB[0] + JOB[2] - 14, JOB[1] + JOB[3] + 2, 4, C["flow_mgmt"])
    # 5 egress
    fw = HB["fw"]
    eg_y = vy + 520
    arrow([(vx, eg_y), (lane_e, eg_y), (lane_e, fw[1] + 30), (fw[0] + fw[2], fw[1] + 30)], C["flow_egress"], dash="6 4", sw=1.8)
    badge(lane_e, eg_y - 40, 5, C["flow_egress"])

    # below the VNet: token example
    ty = vy + 580
    chip(vx, ty, vw, None, "Why a bug in the pooled app can't read another tenant's documents", [
        "A contoso user's token carries role Tenant.contoso and group sg-aiadv-contoso-users. The app exchanges it "
        "(on-behalf-of) for a storage token and a search token that are still that user's.",
        "Storage holds a role assignment for sg-aiadv-contoso-users on container 'contoso' only; Search on index "
        "'contoso' only. If the code asks for container 'adatum', Azure returns 403.",
        "The app's own managed identity has NO data role on storage or search. It only pulls images and writes "
        "telemetry. Model calls carry the user's token to the gateway, which keys token limits on Tenant.<code>.",
    ], title_size=14, sub_size=12, sec=True)

    by = top + main_h + 25
    bottom = notes_band(by, W, [
        ("What is weaker than Tiers 1 and 2 (say it first)", [
            "One process serves every tenant: a memory or cache bug could mix answers. Mitigated by tenant + user",
            "cache keys and no semantic cache, not eliminated. One Azure OpenAI quota and one outage domain for",
            "all tenants; gateway limits keep it fair. No per-tenant network path or CMK on logs. A regulator or",
            "client who asks 'is anything of ours processed alongside other clients?' gets a yes.",
        ], {"sec": True}),
        ("What it costs (approx. list price, USD/month)", [
            "Shared per pool: App Gateway ~400, APIM ~700 (Standard v2*), Search S1 x2 ~490, app replicas ~120,",
            "Log Analytics ~80, Azure OpenAI pay per token. About 1,800 per pool.",
            "Per tenant: a container, an index, an encryption scope, a group, a job identity: ~5 + tokens.",
            "At 45 tenants (the cap, under S1's 50 indexes): ~45 per tenant. Onboarding: same day.",
            "*Premium APIM (internal VNet mode, as built today) is ~2,800: ~90 per tenant at 45.",
        ], {}),
        ("Fits / doesn't fit", [
            "Fits: internal Chatham tools, standard-content products (market commentary, rate and hedge",
            "explainers over Chatham's own research), trials and proofs of concept, small clients whose",
            "data classification is internal or public and whose contract allows logical isolation.",
            "Doesn't fit: confidential client documents, client-specific models or fine-tunes, PTU, CMK",
            "requirements on everything, or a client-owned network path. Those go to Tier 2 or Tier 1.",
        ], {}),
    ])
    H = legend(bottom + 20, W, [("pt", "Owned by Platform Engineering (P&T)"),
                                 ("shared", "Shared by every tenant in the pool"),
                                 ("cli", "Per tenant (partition, identity or limit)"),
                                 ("ext", "Users")],
               [(1, C["flow_user"], "User path: one host name -> pool App Gateway -> pooled app (tenant from the token)"),
                (2, C["flow_mgmt"], "Data path on the user's own token: Azure checks container- and index-scoped roles"),
                (3, C["flow_model"], "Model path: user's token -> AI gateway (per-tenant limits) -> shared Azure OpenAI"),
                (4, C["flow_mgmt"], "Ingestion: per-tenant job identity -> that tenant's container and index only"),
                (5, C["flow_egress"], "Egress: pool workload subnets -> hub firewall (UDR)")],
               "Sources: docs/adr/0014-isolation-tiers.md, docs/architecture/isolation-tiers.md, terraform/stamps/pool. "
               "Names are the example config.") + 20
    save(HERE / "tier3-pooled", W, H, "tier3-pooled", "Tier 3: pooled")


if __name__ == "__main__":
    tier2()
    tier3()
