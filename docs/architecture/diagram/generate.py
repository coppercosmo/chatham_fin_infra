#!/usr/bin/env python3
"""Generate the full multi-client solution architecture diagram as SVG.

Source of truth for docs/architecture/diagram/solution-architecture.svg, the draw.io files (.drawio and
.drawio.svg, editable in app.diagrams.net with Azure icons) and the PNG rendered from the SVG.
Edit this file, then run:

    python3 docs/architecture/diagram/generate.py
    node docs/architecture/diagram/render-png.mjs      # optional, needs Playwright + Chromium

Everything drawn here maps to Terraform in this repo (module names are shown in the boxes) or
to something Platform Engineering (P&T) owns, which is coloured differently.
"""
from html import escape
from pathlib import Path

from drawlib import *  # noqa: F401,F403  palette C and the chip/arrow/section primitives

W, H = 3300, 0  # H is set once the legend position is known
OUT = Path(__file__).with_name("solution-architecture.svg")
OUT_DRAWIO = Path(__file__).with_name("solution-architecture.drawio")
OUT_DRAWIO_SVG = Path(__file__).with_name("solution-architecture.drawio.svg")

# ================================================================= canvas + markers
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
out.append("<defs>")
for col in sorted({C["flow_user"], C["flow_model"], C["flow_egress"], C["flow_mgmt"], C["flow_logs"], C["line"]}):
    out.append(f'<marker id="ah-{col[1:]}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
               f'markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
out.append("</defs>")
out.append(f'<rect width="100%" height="100%" fill="{C["bg"]}"/>')

text(30, 46, "Chatham AI Advisory hosting platform on Azure: multi-client solution architecture", 28, 700)
text(30, 72, "One subscription per client (ADR 0001), built from the same Terraform stamp, inside Platform "
     "Engineering's landing zone. Every client resource below is private; nothing is shared between clients.",
     15, 400, fill=C["muted"])

# ================================================================= 1. governance band (P&T)
gx, gy, gw, gh = 30, 95, W - 60, 235
section(gx, gy, gw, gh, "Entra ID tenant and governance  (owned by Platform Engineering / P&T)", "pt",
        "ADR 0002: AI Advisory is a landing-zone consumer. P&T owns hierarchy, policy, identity and connectivity; "
        "we build inside their guardrails.")
# management group tree
mx, my = gx + 20, gy + 88
chip(mx, my, 150, 40, "Tenant root MG")
chip(mx + 170, my, 190, 40, "Chatham MG", ["P&T policy initiatives"])
chip(mx + 380, my - 22, 170, 36, "Platform MG", ["hub, identity, mgmt subs"], sub_size=10)
chip(mx + 380, my + 26, 170, 36, "Landing zones / Corp MG")
chip(mx + 570, my + 26, 210, 40, "AI Advisory MG", ["AI guardrails (policy/ proposals)"], sec=True)
chip(mx + 800, my - 4, 200, 36, "sub: AI Advisory Platform", [], fill=C["plat_fill"], stroke=C["plat_stroke"])
chip(mx + 800, my + 44, 200, 36, "AI Advisory / Clients MG")
for i, nm in enumerate(["sub: chatham (ring 0)", "sub: acme (ring 1)", "sub: meridian (ring 2)"]):
    chip(mx + 1020, my - 22 + i * 40, 200, 34, nm, fill=C["cli_fill"], stroke=C["cli_stroke"])
for a, b in [((mx + 150, my + 20), (mx + 170, my + 20)), ((mx + 360, my + 20), (mx + 380, my - 4)),
             ((mx + 360, my + 20), (mx + 380, my + 44)), ((mx + 550, my + 44), (mx + 570, my + 46)),
             ((mx + 780, my + 46), (mx + 800, my + 14)), ((mx + 780, my + 46), (mx + 800, my + 62)),
             ((mx + 1000, my + 62), (mx + 1020, my - 5)), ((mx + 1000, my + 62), (mx + 1020, my + 35)),
             ((mx + 1000, my + 62), (mx + 1020, my + 75))]:
    arrow([a, b], C["line"], sw=1.2)
text(mx, my + 120, "Subscription vending: P&T template per client (MG placement, IPAM /22, Entra groups, budget "
     "owner, AOAI quota request)", 12, fill=C["muted"])
# P&T services
px0 = gx + 1290
svc = [
    ("Azure Policy", ["deny public endpoints, allowed regions,", "tags, DINE private DNS, diagnostics"]),
    ("Entra ID groups + PIM", ["sg-aiadv-<client>-readers / -operators", "-aks-admins (PIM eligible)"]),
    ("Defender for Cloud / Sentinel", ["CSPM + workload protection", "(incl. Defender for Containers)"]),
    ("IPAM + DDoS Network Protection", ["spoke CIDRs, DDoS plan on", "public IPs (policy)"]),
    ("Policy as code in CI", ["Checkov mirrors P&T rules;", "policy/ = AI guardrail proposals"]),
]
for i, (t, s) in enumerate(svc):
    chip(px0 + i * 390, gy + 62, 375, 62, t, s, fill=C["pt_fill"], stroke=C["pt_stroke"],
         sec=(t == "Azure Policy"))
text(px0, gy + 150, "Azure Policy add-on (Gatekeeper) enforces the same initiatives inside every AKS cluster. "
     "Exemptions are time-boxed and recorded in an ADR.", 12, fill=C["muted"])

# ================================================================= 2. main band
top = 380
COL_BOTTOM = []

# ---------------------------------------------------------------- users / edge column
ux, uw = 30, 360
section(ux, top, uw, None, "Users and edge", "ext")
USER_Y = {}
uy = top + 60
for key, t, sub_, kw in [
    ("acme", "acme analysts (insurance): ExpressRoute",
     ["acme's own circuit -> hub ExpressRoute gateway", "-> firewall: acme ranges to acme AGW:443 only",
      "acme.ai.<domain>, private only (ADR 0013)"], {}),
    ("fabrikam", "fabrikam analysts (bank): site-to-site VPN",
     ["IPsec IKEv2 to hub VPN gateway, BGP off", "home 172.16.40.0/24 NAT'd to 100.64.12.0/24",
      "(same stamp as acme; column not drawn)"], {}),
    ("woodgrove", "woodgrove analysts (bank on Azure): Private Link",
     ["Private endpoint in woodgrove's OWN subscription", "-> App Gateway Private Link. No hub routing,",
      "IP overlap irrelevant (column not drawn)"], {"sec": True}),
    ("meridian", "meridian analysts (asset manager)",
     ["Internet, from 198.51.100.0/24 only", "NSG + WAF IP allow-list", "meridian.ai.<domain>"], {}),
    ("chatham", "Chatham engagement team", ["Corp network, Entra ID SSO + PIM"], {}),
    ("fd", "Azure Front Door Premium (optional)",
     ["Global edge for internet, multi-region", "clients; WAF at edge; reaches the", "client App Gateway via Private Link"],
     {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
    ("dns", "DNS (P&T)",
     ["<client>.ai.<domain> -> App Gateway", "private IP (x.x.2.10) in client spoke.", "Client DNS forwards only its own zone",
      "to the resolver inbound IP 10.0.1.4"], {"fill": C["pt_fill"], "stroke": C["pt_stroke"]}),
]:
    h_ = chip(ux + 15, uy, uw - 30, None, t, sub_, **kw)
    USER_Y[key] = (uy, h_)
    uy += h_ + 14
badge(ux + uw - 24, USER_Y["woodgrove"][0] + 14, 5, C["flow_user"])
text(ux + 15, uy + 30, "Identity for end users", 14, 700)
lines(ux + 15, uy + 52, [
    "Client staff sign in to the app with Entra ID",
    "(B2B guests or the client's own tenant via",
    "app registration); app enforces roles.",
    "No user ever reaches a model, vault or",
    "storage account directly.",
], 12, fill=C["muted"])
text(ux + 15, uy + 160, "Operators", 14, 700)
lines(ux + 15, uy + 182, [
    "Readers: standing Reader + AKS RBAC Reader.",
    "Writers: PIM-elevated Contributor, time-",
    "bound, approved. Bastion (hub) for private",
    "AKS API / troubleshooting.",
], 12, fill=C["muted"])

# ---------------------------------------------------------------- hub column (P&T)
hx, hw = 410, 390
section(hx, top, hw, None, "Connectivity subscription: hub VNet", "pt", "Owned by P&T (ADR 0002, 0003)")
hub_items = [
    ("ExpressRoute gateway (ErGw1AZ)", ["Client circuits linked by authorization key",
                                        "VNet-to-VNet over circuits OFF;", "no circuit-to-circuit transit"]),
    ("VPN gateway (VpnGw2AZ, active-active)", ["IPsec IKEv2 per client, BGP OFF so no", "client learns another's routes;",
                                               "static NAT for overlapping ranges"]),
    ("Azure Firewall (Premium)", ["0.0.0.0/0 from every spoke (UDR)", "GatewaySubnet: each spoke -> firewall",
                                  "One rule per client: its ranges ->", "its own AGW IP:443. Default deny.",
                                  "FQDN allow-list egress, IDPS", "spoke-to-spoke DENIED"]),
    ("Private DNS Resolver", ["Spokes use it as DNS server", "Inbound endpoint 10.0.1.4 for client", "DNS conditional forwarders"]),
    ("privatelink.* Private DNS zones", ["vaultcore, openai, blob, search,", "cognitiveservices, azmk8s.io", "Records created by DINE policy"]),
    ("Linked per-client zones", ["<client>.ai.<domain> -> AGW IP (routed", "clients), <apim>.azure-api.net, ACA env",
                                 "zone (linked to resolver VNet by P&T)"]),
    ("Azure Bastion", ["Jump path to private AKS API", "and troubleshooting VMs"]),
    ("DDoS Network Protection plan", ["Applied to public IPs by policy"]),
]
yy = top + 70
HUB_Y = {}
for t, s in hub_items:
    h = chip(hx + 15, yy, hw - 30, None, t, s, fill="#ffffff", stroke=C["pt_stroke"],
             sec=t.startswith("Azure Firewall"))
    HUB_Y[" ".join(t.split(" ")[:2])] = (yy, h)
    yy += h + 14
text(hx + 15, yy + 14, "Hub <-> spoke VNet peering", 14, 700)
lines(hx + 15, yy + 36, [
    "Spoke side created by the stamp; hub side",
    "by P&T (modules/hub-connectivity). Gateway",
    "transit only for ExpressRoute/VPN clients.",
    "Spokes never peer with each other.",
    "Standalone mode (chatham sandbox): no",
    "peering, stamp creates its own privatelink",
    "zones, Azure-provided DNS.",
], 12, fill=C["muted"])
FW_Y = HUB_Y["Azure Firewall"][0] + HUB_Y["Azure Firewall"][1] // 2

# ---------------------------------------------------------------- client stamps
clients = [
    dict(code="chatham", title="Client subscription: chatham (internal canary)", ring=0, cidr="10.100.0.0/22",
         compute="aca", ingress=None, mode="standalone", gpu=False, search=False, cs=False,
         apim="Developer_1, 100k TPM (gateway pilot)", backends=["aoai-primary"],
         models=["chat: gpt-4o-mini (DataZoneStandard)"], logs="90 days", budget="USD 300 / month",
         locks=False),
    dict(code="acme", title="Client subscription: acme (insurance)", ring=1, cidr="10.100.4.0/22",
         compute="aca", ingress="private", mode="landing zone", gpu=False, search=True, cs=True,
         client_net="172.16.0.0/16",
         apim="Premium_1 (zones), 40k TPM, Prompt Shields", backends=["aoai-primary"],
         models=["chat: gpt-4o (DataZoneStandard)", "embeddings: text-embedding-3-large"],
         logs="365 days (client records policy)", budget="USD 5,000 / month", locks=True),
    dict(code="meridian", title="Client subscription: meridian (asset manager)", ring=2, cidr="10.100.8.0/22",
         compute="aks", ingress="public", mode="landing zone", gpu=True, search=True, cs=False,
         apim="Premium_1 (zones), 30k TPM, 2 backends", backends=["aoai-primary", "aoai-centralus"],
         models=["chat: gpt-4o (DataZoneStandard)", "embeddings: text-embedding-3-large"],
         logs="90 days", budget="USD 12,000 / month", locks=True),
]
cx0, cw, cg = 820, 600, 20
AGW_POS, APIM_POS, APP_POS = {}, {}, {}


def octets(cidr):
    a, b, c, _ = cidr.split("/")[0].split(".")
    return a, b, int(c)


for i, cl in enumerate(clients):
    x = cx0 + i * (cw + cg)
    a, b, c3 = octets(cl["cidr"])
    p = f"{a}.{b}"
    section(x, top, cw, None, cl["title"], "cli",
            f'Ring {cl["ring"]}  |  {cl["mode"]}  |  compute: '
            f'{"Container Apps" if cl["compute"] == "aca" else "AKS (dedicated, private)"}  |  '
            f'ingress: {cl["ingress"] or "none (internal only)"}')
    # ---- spoke VNet (vertical flow; boxes sized to their contents)
    vx, vy, vw = x + 14, top + 60, cw - 28
    vnet_slot = slot()
    text(vx + 12, vy + 22, f'Spoke VNet  vnet-{cl["code"]}-prd-eus2  {cl["cidr"]}', 14, 700, fill=C["cli_stroke"])
    text(vx + vw - 12, vy + 22,
         "UDR 0.0.0.0/0 -> hub firewall" if cl["mode"] != "standalone" else "standalone: own privatelink zones",
         11, 600, "end", C["sec"] if cl["mode"] != "standalone" else C["muted"])
    sx, sw_ = vx + 12, vw - 24
    S = dict(title_size=12, sub_size=10)

    def subnet(y0, label):
        sl = slot()
        text(sx + 10, y0 + 18, label, 11, 600, fill=C["muted"])
        return sl

    def close(sl, y0, y1):
        rect(sx, y0, sw_, y1 - y0, C["subnet_fill"], C["subnet_stroke"], rx=8, dash="5 3", at=sl)

    # snet-agw
    sy = vy + 36
    src = f'{cl["client_net"]} only' if cl.get("client_net") else "approved sources"
    sl = subnet(sy, f"snet-agw  {p}.{c3 + 2}.0/24   NSG: GatewayManager, AzureLB, 443 from {src}")
    if cl["ingress"]:
        fe = (f"Private frontend {p}.{c3 + 2}.10, no public IP" if cl["ingress"] == "private"
              else f"Public IP (zonal) + private {p}.{c3 + 2}.10; NSG + WAF allow-list")
        a_sub = [fe] + ([f'Return route {cl["client_net"]} -> hub firewall'] if cl.get("client_net") else []) + [
                 "Listener cert from client Key Vault via id-agw (versionless)",
                 "TLS 1.2+ policy, SNI, HTTPS re-encrypt to backend",
                 "Streaming on, 180s timeout, autoscale 1-5"]
        w_sub = ["Prevention mode; DRS 2.1 + Bot Manager 1.1",
                 "Prompt fields excluded from SQLI/XSS only",
                 "Rate limit per client IP" + ("; IP allow-list" if cl["ingress"] == "public" else ""),
                 "Access + firewall logs -> client LAW"]
        aw = (sw_ - 30) // 2
        hh = max(chip_h(aw, "App Gateway WAF_v2 (modules/app-gateway)", a_sub, 12, 10),
                 chip_h(aw, "WAF policy (per client)", w_sub, 12, 10))
        chip(sx + 10, sy + 28, aw, hh, "App Gateway WAF_v2 (modules/app-gateway)", a_sub, sec=True, **S)
        chip(sx + 20 + aw, sy + 28, aw, hh, "WAF policy (per client)", w_sub, sec=True, **S)
        AGW_POS[cl["code"]] = (sx + 10, sy + 50)
        sy2 = sy + 28 + hh + 10
    else:
        text(sx + 10, sy + 44, "Not deployed: internal canary, reached by the platform team only.",
             12, italic=True, fill=C["muted"])
        text(sx + 10, sy + 62, "The same module switches on with an ingress block in clients/chatham.", 12,
             italic=True, fill=C["muted"])
        sy2 = sy + 76
    close(sl, sy, sy2)

    # workload subnet
    wy = sy2 + 10
    half = (sw_ - 30) // 2
    if cl["compute"] == "aca":
        sl = subnet(wy, f"snet-apps  {p}.{c3}.0/24   delegated to Microsoft.App/environments")
        cy_ = wy + 28
        cy_ += chip(sx + 10, cy_, sw_ - 20, None, "Container Apps environment (internal LB, workload profiles)",
                    ["modules/container-apps; zone redundant; static internal IP; private DNS zone for the env domain;"
                     " logs to the client Log Analytics workspace"], **S) + 10
        app_sub = ["User-assigned id-<client>-app", "Image by digest from shared ACR",
                   "AZURE_OPENAI_ENDPOINT = AI gateway URL"]
        job_sub = ["Ingestion / indexing", "Evaluation runs", "Same identity, same limits"]
        hh = max(chip_h(half, "ca-<client>-api", app_sub, 12, 10), chip_h(half, "Container Apps Jobs", job_sub, 12, 10))
        chip(sx + 10, cy_, half, hh, "ca-<client>-api", app_sub, **S)
        chip(sx + 20 + half, cy_, half, hh, "Container Apps Jobs", job_sub, **S)
        APP_POS[cl["code"]] = (sx + 10 + half // 2, cy_ + hh)
        cy_ += hh + 18
        text(sx + 10, cy_, "App calls models only through the AI gateway (no direct model role).", 11, fill=C["muted"])
        text(sx + 10, cy_ + 16, "Key Vault, Storage and Search via private endpoints, resource-scoped roles.", 11,
             fill=C["muted"])
        cy_ += 28
    else:
        sl = subnet(wy, f"snet-aks  {p}.{c3}.0/24   nodes only; pods in overlay 192.168.0.0/16")
        cy_ = wy + 28
        cy_ += chip(sx + 10, cy_, sw_ - 20, None, "AKS private cluster (modules/aks), Standard tier",
                    ["Entra ID only + Azure RBAC, local accounts off; API server via private DNS (P&T azmk8s zone)",
                     "CNI Overlay + Cilium; UDR egress; Azure Policy add-on; Key Vault CSI; patch auto-upgrade"],
                    sec=True, **S) + 10
        pw = (sw_ - 40) // 3
        pools = [("system pool", ["3 zones, critical add-ons only"]),
                 ("user pool", ["App pods, autoscale, Azure Linux, host encryption"]),
                 ("gpu pool" if cl["gpu"] else "gpu pool (off)", ["A100, tainted, scales from 0 (self-hosted models)"])]
        hh = max(chip_h(pw, t, s_, 12, 10) for t, s_ in pools)
        for j, (t, s_) in enumerate(pools):
            chip(sx + 10 + j * (pw + 10), cy_, pw, hh, t, s_, **S)
        cy_ += hh + 10
        ng = ["Internal LB " + f"{p}.{c3}.250", "TLS cert from Key Vault", "App Gateway backend"]
        ns = ["Workload identity -> id-<client>-app", "Restricted PSS, default-deny netpol", "Flux (GitOps) deploys kubernetes/"]
        hh = max(chip_h(half, "Managed NGINX (internal)", ng, 12, 10), chip_h(half, "ns advisor: advisor-api", ns, 12, 10))
        chip(sx + 10, cy_, half, hh, "Managed NGINX (internal)", ng, **S)
        chip(sx + 20 + half, cy_, half, hh, "ns advisor: advisor-api", ns, **S)
        APP_POS[cl["code"]] = (sx + 20 + half + half // 2, cy_ + hh)
        cy_ += hh + 18
        text(sx + 10, cy_, "Kubelet + control-plane identities are user-assigned; AcrPull granted first.", 11,
             fill=C["muted"])
        cy_ += 12
    close(sl, wy, cy_ + 10)

    # snet-apim
    ay = cy_ + 20
    sl = subnet(ay, f"snet-apim  {p}.{c3 + 1}.64/26   NSG: ApiManagement:3443, AzureLB:6390, 443 from workload")
    apim_sub = [cl["apim"],
                "validate-azure-ad-token (only id-<client>-app, no keys) -> "
                + ("llm-content-safety (Prompt Shields) -> " if cl["cs"] else "") + "llm-token-limit per caller",
                "llm-emit-token-metric (Client, CallerAppId) -> managed identity to models -> "
                + ("priority failover " + " -> ".join(cl["backends"]) if len(cl["backends"]) > 1
                   else "backend aoai-primary"),
                "Circuit breaker per backend (429/5xx, honours Retry-After); prompt bodies not logged by default",
                "Private DNS zone <apim>.azure-api.net; gateway + token logs -> client LAW / App Insights"]
    hh = chip(sx + 10, ay + 28, sw_ - 20, None, "AI gateway: API Management, internal VNet (modules/ai-gateway)",
              apim_sub, sec=True, **S)
    APIM_POS[cl["code"]] = (sx + sw_ // 2, ay + 28)
    close(sl, ay, ay + 28 + hh + 10)

    # snet-pe
    ey = ay + 28 + hh + 20
    sl = subnet(ey, f"snet-pe  {p}.{c3 + 1}.0/26   NSG: 443 only from workload, agw, apim subnets")
    pes = ["pe-kv", "pe-blob", "pe-oai"] + (["pe-srch"] if cl["search"] else []) + (["pe-cs"] if cl["cs"] else [])
    pw = (sw_ - 20 - 8 * (len(pes) - 1)) // len(pes)
    hh = max(chip_h(pw, pe, ["private endpoint"], 12, 10) for pe in pes)
    for j, pe in enumerate(pes):
        chip(sx + 10 + j * (pw + 8), ey + 28, pw, hh, pe, ["private endpoint"], **S)
    close(sl, ey, ey + 28 + hh + 10)
    vh = ey + 28 + hh + 22 - vy
    rect(vx, vy, vw, vh, C["vnet_fill"], C["vnet_stroke"], rx=10, sw=1.8, at=vnet_slot)

    # ---- PaaS (outside VNet, reached only via PEs)
    py = vy + vh + 14
    text(x + 14, py + 14, "PaaS (public network access disabled; reached only through the private endpoints above)",
         12, 600, fill=C["cli_stroke"])
    paas = [
        ("Azure OpenAI", ["oai-<client>  (modules/ai-services)", "local auth OFF, Entra only", "outbound restricted to own",
                          "Search + blob hosts", *cl["models"], "NoAutoUpgrade (ring rollout)"]),
        ("Key Vault (Premium)", ["RBAC mode, purge protection", "TLS certs, 3rd-party secrets", "Secrets User: app, agw,",
                                 "AKS app-routing"]),
        ("Storage (documents)", ["shared keys OFF, ZRS", "versioning + soft delete", "infra double encryption",
                                 "Blob Data Contributor: app"]),
    ]
    if cl["search"]:
        paas.append(("Azure AI Search", ["keys OFF, 3 replicas (SLA)", "own MI -> blob, AOAI", "Index Data Reader: app"]))
    if cl["cs"]:
        paas.append(("Content Safety", ["Prompt Shields for", "the AI gateway", "keys OFF"]))
    if len(cl["backends"]) > 1:
        paas.append(("AOAI centralus", ["secondary backend,", "same US data zone", "(gateway failover)"]))
    bw = (cw - 28 - 16) // 3
    rowy, rowh = py + 24, 0
    for r in range(0, len(paas), 3):
        row = paas[r:r + 3]
        rowy += rowh + (8 if r else 0)
        rowh = max(chip_h(bw, t, s_, 12, 10) for t, s_ in row)
        for j, (t, s_) in enumerate(row):
            chip(x + 14 + j * (bw + 8), rowy, bw, rowh, t, s_, title_size=12, sub_size=10, sec=t == "Azure OpenAI")

    # ---- identities
    iy = rowy + rowh + 12
    text(x + 14, iy + 14, "Managed identities (no secrets anywhere)", 12, 600, fill=C["cli_stroke"])
    ids = [("id-<client>-app", ["workload: KV, blob, Search,", "metrics; AKS: federated to", "advisor:advisor-api"]),
           ("APIM system MI", ["OpenAI User on each", "backend; CS User;", "App Insights publisher"])]
    if cl["ingress"]:
        ids.append(("id-<client>-agw", ["Key Vault Secrets User", "(listener cert only)"]))
    if cl["compute"] == "aks":
        ids.append(("id-<client>-aks-cp / kubelet", ["Network Contributor on", "subnet + UDR; AcrPull"]))
    n = len(ids)
    bw = (cw - 28 - 8 * (n - 1)) // n
    idh = max(chip_h(bw, t, s_, 12, 10) for t, s_ in ids)
    for j, (t, s_) in enumerate(ids):
        chip(x + 14 + j * (bw + 8), iy + 24, bw, idh, t, s_, title_size=12, sub_size=10)

    # ---- operations
    oy = iy + 24 + idh + 12
    text(x + 14, oy + 14, "Operations and guardrails in this subscription", 12, 600, fill=C["cli_stroke"])
    ops = [("Log Analytics + App Insights", [f"retention {cl['logs']}", "diag: KV, AOAI, blob, Search,",
                                              "AGW/WAF, APIM, AKS audit", "local auth OFF"]),
           ("Alerts + budget", ["AOAI 429 rate, tokens vs quota,", "5xx, KV Forbidden",
                                f"budget {cl['budget']}", "-> shared action group"]),
           ("Locks + RBAC", ["CanNotDelete on KV, storage,", "AOAI" + ("" if cl["locks"] else " (off for canary)"),
                             "Reader group: standing", "Operators: PIM only"])]
    bw = (cw - 28 - 16) // 3
    oh = max(chip_h(bw, t, s_, 12, 10) for t, s_ in ops)
    for j, (t, s_) in enumerate(ops):
        chip(x + 14 + j * (bw + 8), oy + 24, bw, oh, t, s_, title_size=12, sub_size=10)
    text(x + 14, oy + 24 + oh + 22, f'Config: terraform/clients/{cl["code"]}/  ~40 lines  |  state: tfstate-{cl["code"]}  |  '
         f'deploy: id-deploy-{cl["code"]}', 11, 600, fill=C["muted"])
    COL_BOTTOM.append(oy + 24 + oh + 40)

# ---------------------------------------------------------------- platform subscription
px, pw_ = cx0 + 3 * (cw + cg), W - 30 - (cx0 + 3 * (cw + cg))
section(px, top, pw_, None, "sub: AI Advisory Platform (shared)", "plat",
        "Holds NO client data (ADR 0001). terraform/platform")
plat = [
    ("Terraform state storage", ["staiadvtfstate<suffix>, GZRS, Entra only", "one container per client: tfstate-<client>",
                                 "versioning + soft delete; access logs -> LAW"]),
    ("Azure Container Registry (Premium)", ["private endpoint, zone redundant", "dedicated data endpoints, 7-day untagged purge",
                                            "images signed (Notation), deployed by digest"]),
    ("Per-client deployment identities", ["id-deploy-<client>: Contributor + RBAC Admin", "constrained by ABAC to a fixed role list",
                                          "OIDC federated to env client-<client> only"]),
    ("Per-client plan identities", ["id-plan-<client>: Reader + state read", "OIDC federated to client-<client>-plan",
                                    "PRs and drift checks can never apply"]),
    ("Platform Log Analytics", ["who read/wrote state, pushed/pulled", "images; 365-day retention"]),
    ("Central ops workbook", ["read-only queries across every client", "workspace; cost per client monthly"]),
    ("Self-hosted runners (planned)", ["in platform VNet for private", "data-plane steps; then state", "account goes private-only"]),
]
yy = top + 70
for t, s in plat:
    h = chip(px + 15, yy, pw_ - 30, None, t, s, fill="#ffffff", stroke=C["plat_stroke"],
             sec=t.startswith("Per-client deployment"))
    yy += h + 14
text(px + 15, yy + 14, "What is shared across clients", 14, 700)
lines(px + 15, yy + 36, [
    "Code (modules, stamp), container images",
    "(same digest promoted by ring), the",
    "registry, state storage and CI. Never:",
    "networks, models, vaults, data, logs,",
    "gateways, clusters or pipeline identities.",
], 12, fill=C["muted"])
ACR_POS = (px + 15, top + 190)
DEPLOY_POS = (px + 15, top + 290)

# ================================================================= close the main band
bottom = max(COL_BOTTOM + [yy + 140]) + 10
for sl_, x_, y_, w_, f_, st_ in PENDING:
    rect(x_, y_, w_, bottom - y_, f_, st_, rx=12, sw=2, at=sl_)

# ================================================================= flows across columns
# 1 client network -> hub gateway -> firewall -> App Gateway (private, ADR 0013)
acme_agw = AGW_POS["acme"]
er_y = HUB_Y["ExpressRoute gateway"][0] + HUB_Y["ExpressRoute gateway"][1] // 2
vpn_y = HUB_Y["VPN gateway"][0] + HUB_Y["VPN gateway"][1] // 2
acme_y = USER_Y["acme"][0] + USER_Y["acme"][1] // 2
fab_y = USER_Y["fabrikam"][0] + USER_Y["fabrikam"][1] // 2
arrow([(ux + uw - 15, acme_y), (ux + uw + 2, acme_y), (ux + uw + 2, er_y), (hx + 13, er_y)], C["flow_user"])
arrow([(ux + uw - 15, fab_y), (ux + uw + 10, fab_y), (ux + uw + 10, vpn_y), (hx + 13, vpn_y)], C["flow_user"])
for gy_ in (er_y, vpn_y):  # both gateways hand client traffic to the firewall (GatewaySubnet route)
    arrow([(hx + 15, gy_ + 12), (hx + 6, gy_ + 12), (hx + 6, FW_Y), (hx + 13, FW_Y)], C["flow_user"], sw=1.8)
arrow([(hx + hw - 15, FW_Y - 14), (hx + hw - 5, FW_Y - 14), (hx + hw - 5, top - 34),
       (acme_agw[0] - 6, top - 34), (acme_agw[0] - 6, acme_agw[1]), (acme_agw[0], acme_agw[1])], C["flow_user"])
badge(hx - 2, er_y, 1, C["flow_user"])
# 2 internet -> meridian AGW public IP
mer_agw = AGW_POS["meridian"]
mer_y = USER_Y["meridian"][0] + USER_Y["meridian"][1] // 2
arrow([(ux + uw - 15, mer_y), (ux + uw + 6, mer_y), (ux + uw + 6, top - 22),
       (mer_agw[0] - 6, top - 22), (mer_agw[0] - 6, mer_agw[1] + 20), (mer_agw[0], mer_agw[1] + 20)],
      C["flow_user"], dash="8 5")
badge(ux + uw + 6, mer_y - 40, 2, C["flow_user"])
# 3 front door (optional) private link
fd_y = USER_Y["fd"][0] + USER_Y["fd"][1] // 2
arrow([(ux + uw - 15, fd_y), (ux + uw + 30, fd_y)], C["flow_user"], dash="3 4")

# 4/5 app -> APIM -> AOAI (drawn inside each client)
for cl in clients:
    ax_, ay_ = APP_POS[cl["code"]]
    mx_, my_ = APIM_POS[cl["code"]]
    rx_ = mx_ + 230  # right edge of the subnet, clear of the notes text
    arrow([(rx_, ay_ + 2), (rx_, my_ - 2)], C["flow_model"], sw=2.6)
    badge(rx_ - 18, my_ - 50, 3, C["flow_model"])
# 6 egress via hub firewall (from acme + meridian spokes)
for code in ("acme", "meridian"):
    i = [c["code"] for c in clients].index(code)
    x = cx0 + i * (cw + cg)
    arrow([(x + cw - 8, top + 60), (x + cw - 8, top - 10), (hx + hw + 8, top - 10), (hx + hw + 8, FW_Y + 14),
           (hx + hw - 13, FW_Y + 14)], C["flow_egress"], dash="6 4", sw=1.8)
badge(hx + hw + 8, FW_Y + 60, 4, C["flow_egress"])

# ================================================================= 3. CI/CD band
cy, ch = bottom + 25, 290
section(30, cy, W - 60, ch, "Delivery: GitHub Actions (ADR 0008) and GitOps", "ext",
        "Same pipeline for every client; each job can only ever authenticate as its own client")
steps = [
    ("Pull request", ["terraform fmt + validate", "terraform test (mocked, offline)", "client-config type-check",
                      "module tests, tflint, actionlint", "Checkov (blocking)"]),
    ("Plan per affected client", ["env client-<c>-plan", "OIDC -> id-plan-<c> (read-only)", "module change = all clients",
                                  "client change = that client"]),
    ("Ring 0: chatham", ["auto on merge to main", "canary + gateway pilot", "evals, latency checks"]),
    ("Ring 1: acme (pilots)", ["env client-acme", "required reviewers", "OIDC -> id-deploy-acme"]),
    ("Ring 2: everyone else", ["env client-<c>, approvals", "max 5 parallel, fail-fast", "e.g. meridian"]),
    ("Nightly drift", ["plan -detailed-exitcode", "per client, read-only", "opens a GitHub issue"]),
    ("Flux (AKS clients)", ["reconciles kubernetes/", "from Git inside the cluster", "CI needs no access to the", "private API server"]),
    ("App releases", ["build once, sign, push to", "ACR; promote the same", "digest ring by ring", "via app_image"]),
]
bw = (W - 60 - 30 - 7 * 14) // 8
for j, (t, s) in enumerate(steps):
    bx = 45 + j * (bw + 14)
    chip(bx, cy + 62, bw, 150, t, s, title_size=13, sub_size=11,
         sec=t.startswith("Ring"))
    if j < 5:
        arrow([(bx + bw, cy + 137), (bx + bw + 13, cy + 137)], C["flow_mgmt"])
text(45, cy + 240, "Apply identities: Contributor + RBAC Administrator limited by an ABAC condition to KV Secrets User, OpenAI User, "
     "Blob Data Contributor/Reader, Search Index Reader, Metrics Publisher, Reader, Network Contributor, Private DNS Zone "
     "Contributor, Managed Identity Operator, AKS RBAC Reader, Cognitive Services User (and AcrPull on the shared ACR only).",
     12, fill=C["muted"])

# ================================================================= 4. legend
ly = cy + ch + 20
H = ly + 165  # canvas height follows the content
section(30, ly, W - 60, H - ly - 20, "Legend", "ext")
lx = 50
for kind, label in [("pt", "Owned by Platform Engineering (P&T)"),
                    ("plat", "AI Advisory shared platform (no client data)"),
                    ("cli", "Per client: client data, nothing shared"),
                    ("ext", "Users, edge, GitHub")]:
    rect(lx, ly + 48, 34, 22, C[f"{kind}_fill"], C[f"{kind}_stroke"], rx=4, sw=2)
    text(lx + 44, ly + 64, label, 13)
    lx += 330
rect(lx, ly + 48, 34, 22, "#ffffff", C["sec"], rx=4, sw=2)
text(lx + 44, ly + 64, "Key security control", 13)
lx += 230
flows = [(1, C["flow_user"], "Private routed path: client network -> ExpressRoute/VPN gateway -> hub firewall (one rule per client) -> App Gateway WAF"),
         (2, C["flow_user"], "Public user path (opt-in): internet -> App Gateway public IP, NSG + WAF allow-list"),
         (3, C["flow_model"], "Model path: app -> AI gateway (Entra token) -> Azure OpenAI private endpoint (gateway MI)"),
         (4, C["flow_egress"], "Egress: every spoke workload subnet -> hub firewall (UDR); spoke-to-spoke denied"),
         (5, C["flow_user"], "Private Link path: client's own Azure VNet -> private endpoint -> App Gateway Private Link (no hub routing)")]
for k, (n, col, label) in enumerate(flows):
    fx = lx + (k % 2) * 760
    fy = ly + 50 + (k // 2) * 28
    badge(fx + 12, fy + 9, n, col)
    text(fx + 30, fy + 14, label, 12)
text(50, ly + 130, "Sources: docs/adr/0001-0013, terraform/stamps/client, terraform/modules/hub-connectivity, terraform/platform, terraform/clients/*. "
     "Addresses and names are the example configs; every value comes from a client's ~40-line tfvars.", 12, fill=C["muted"])

out.append("</svg>")
out[0] = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'

OUT.write_text("\n".join(out), encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")

# ---------------------------------------------------------------- draw.io outputs
# solution-architecture.drawio      native file: open in app.diagrams.net / draw.io desktop / VS Code extension
# solution-architecture.drawio.svg  same diagram embedded in an SVG: GitHub renders it, draw.io opens it editable
mxfile = (
    '<mxfile host="generate.py" type="device"><diagram id="solution-architecture" name="Solution architecture">'
    f'<mxGraphModel dx="{W}" dy="{H}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
    f'fold="1" page="1" pageScale="1" pageWidth="{W}" pageHeight="{H}" background="{C["bg"]}" math="0" shadow="0">'
    '<root><mxCell id="0"/><mxCell id="1" parent="0"/>' + "".join(c for c in CELLS if c)
    + "</root></mxGraphModel></diagram></mxfile>")
OUT_DRAWIO.write_text(mxfile, encoding="utf-8")
print(f"wrote {OUT_DRAWIO} ({OUT_DRAWIO.stat().st_size // 1024} KB, {sum(1 for c in CELLS if c)} shapes)")
embedded = out.copy()
embedded[0] = embedded[0].replace("<svg ", f'<svg content="{escape(mxfile)}" ', 1)
OUT_DRAWIO_SVG.write_text("\n".join(embedded), encoding="utf-8")
print(f"wrote {OUT_DRAWIO_SVG} ({OUT_DRAWIO_SVG.stat().st_size // 1024} KB)")
