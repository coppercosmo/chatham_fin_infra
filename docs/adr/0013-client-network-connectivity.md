# ADR 0013: Client network connectivity (Private Link first, then ExpressRoute or VPN through the hub)

- Status: Accepted, amends 0010
- Date: 2026-11-16

## Context
Clients' analysts mostly work on their own corporate networks, and regulated clients want the path to
their AI environment to be private end to end, not "internet plus a WAF". ADR 0010 gave each client a
private front door (an App Gateway WAF_v2 with a private IP in their spoke) and said users "arrive
through the hub (ExpressRoute/VPN)". It didn't say how, and that is where multi-client isolation is
easiest to get wrong:

- P&T's hub is **shared**. Connecting client A's network to it must not connect client A to client B,
  to client B's spoke, or to anything in client A's spoke other than the front door.
- Client networks reuse the same private ranges. Two clients on `10.0.0.0/8`, or a client range that
  overlaps a spoke, can't be routed through one hub without translation.
- P&T owns the hub, gateways, firewall, DNS and IPAM (ADR 0002). We can't edit their routes; we have
  to hand them something they can apply safely and repeatably.
- Many of Chatham's clients (banks, insurers, asset managers) already run in Azure, often in their own
  tenant, with their own ExpressRoute to it.

## Options considered

| Option | Isolation between clients | IP overlap | Who runs it | Notes |
|---|---|---|---|---|
| **A. Private Link** to the client's App Gateway; client creates a private endpoint in their own Azure | **Strongest**: no routing at all, nothing shared in the path | Irrelevant | Client creates the endpoint; we approve it | Needs the client to be on Azure. Chosen as the preferred option. |
| **B. ExpressRoute** circuit linked to P&T's hub ExpressRoute gateway | Good **with** per-client routes, firewall rules and NSGs; route *prefixes* of other spokes are still advertised | Must be unique (no NAT on ExpressRoute gateways) | P&T | Chosen for clients not on Azure that have ExpressRoute. |
| **C. Site-to-site VPN** to P&T's hub VPN gateway | Good with the same controls, BGP off, static routes | NAT on the gateway (VpnGw2AZ+) | P&T | Chosen for smaller clients, quick starts and ExpressRoute backup. |
| D. Dedicated hub (or gateway) per client | Very strong | Per hub | P&T, N times | Hundreds of USD/month of gateways per client, more hubs for P&T to run and audit. Kept as an exception for a client whose risk team rejects B/C and can't do A. |
| E. Virtual WAN with custom route tables and branch-to-branch off | Good, policy-driven | Needs NAT or uniqueness | P&T | Valid if P&T already runs Virtual WAN; the per-client contract below maps onto it. Not assumed, since P&T's hub is a hub VNet today. |
| F. Public frontend + IP allow-list only | Weakest (internet path) | n/a | Us | Already supported as `none` with `frontend_mode = "public"` (e.g. meridian). Not "private" for clients that ask. |

## Decision
One per-client input, `client_connectivity`, with four types: `privatelink`, `expressroute`, `vpn`,
`none` (default). **Private Link is the recommended answer for any client already on Azure**;
ExpressRoute or VPN through P&T's hub otherwise.

### Private Link (spoke only, no hub change)
- App Gateway Private Link on the client's **private** frontend, in a dedicated `snet-agw-pl` subnet.
- The App Gateway NSG admits 443 only from that subnet.
- We approve endpoints only from the client's listed subscriptions (`scripts/approve-private-endpoints.sh`).
- Because App Gateway Private Link isn't supported on the private-only deployment, these gateways keep
  a control-plane public IP with **no listener**. This amends ADR 0010, where a private frontend meant
  no public IP at all.

### ExpressRoute and VPN (spoke + P&T's hub)
In the spoke (`terraform/stamps/client`), all generated from `on_prem_prefixes`:
- App Gateway NSG and WAF allow-list: the client's ranges only, never the `VirtualNetwork` tag.
- `snet-agw` route table: the client's ranges back through the hub firewall, gateway route propagation off.
- Peering uses the hub gateway only once P&T confirms gateway transit (`hub.gateway_transit`).
- Output `hub_connectivity_request`: the exact object P&T's hub module takes.

In the hub (`terraform/modules/hub-connectivity`, proposed to P&T like `policy/`):
- One connection per client (ExpressRoute with the client's authorization key, or IPsec IKEv2 with a
  strong policy, active-active, **BGP off**, optional static NAT).
- ExpressRoute gateway with VNet-to-VNet and Virtual WAN traffic over circuits **off**.
- A GatewaySubnet route per client spoke to the firewall, and one firewall rule collection group per
  client: its ranges to its App Gateway IP on 443. Default deny.
- A private DNS zone per client host name, answered through the DNS Private Resolver inbound endpoint.
- Hub-side peering with gateway transit only for routed clients.
- Plan-time refusal of any overlap between the hub, spokes and client ranges, duplicate firewall
  priorities, more circuits than the gateway SKU allows, or NAT on a gateway too small for it.

Secrets (VPN pre-shared keys, ExpressRoute authorization keys) go from the client to P&T's Key Vault
and are read by P&T's pipeline. They are never in this repo, our state, or the request object.

## Consequences
- Onboarding a routed client takes three applies across two teams (stamp, hub, stamp again). The
  middle step is P&T's, so it is bounded by their change process; the request object makes it a
  copy-paste, not a design task. Private Link is one apply plus an approval.
- P&T carries the shared gateway costs and capacity. ErGw1AZ links 4 circuits; more ExpressRoute
  clients mean a larger SKU. Shared gateway bandwidth is a noisy-neighbour risk we monitor per connection.
- Routed clients can still see that other spokes' prefixes exist (ExpressRoute advertisements) and
  could resolve other clients' host names through the resolver. Neither gives access. Clients who
  won't accept that metadata exposure get Private Link, or option D as a recorded exception.
- Overlapping client ranges become an onboarding question, answered by NAT (VPN), a client-side NAT
  (ExpressRoute), or Private Link. CI fails before Azure would.
- The firewall now sits in the user path for routed clients: P&T's firewall capacity and IDPS
  settings affect latency for streaming completions. Measured in ring 1.

## Revisit when
- P&T moves the hub to Virtual WAN (re-express the module as routing intent + per-connection routing).
- App Gateway supports Private Link on the private-only deployment (drop the control-plane public IP).
- A client needs both Private Link and on-prem access without Azure of their own (consider Front Door
  Premium with Private Link origins, already noted in ADR 0010).
