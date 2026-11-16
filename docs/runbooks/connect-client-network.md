# Runbook: connect a client's network (ADR 0013)

How a client's own network gets a private path to their environment. Pick the type first; the
reasoning is in [client-connectivity.md](../architecture/client-connectivity.md).

| Client situation | `client_connectivity.type` |
|---|---|
| Already runs in Azure (any tenant) | `privatelink` (preferred) |
| Not on Azure, has or will order ExpressRoute | `expressroute` |
| Not on Azure, no ExpressRoute, or needs a backup path | `vpn` |
| Internet users, or Chatham staff only | `none` |

## Private Link

1. In `terraform/clients/<code>/terraform.tfvars`:
   ```hcl
   client_connectivity = {
     type         = "privatelink"
     private_link = { consumer_subscription_ids = ["<client's subscription id>"] }
   }
   ```
   `ingress` must be set with `frontend_mode = "private"`. PR, plan, merge, ring rollout.
2. Send the client `terraform output private_link_offer`: the App Gateway resource ID and the target
   sub-resource `private`. They create a private endpoint in their VNet with those values (cross-tenant
   endpoints must use the resource ID, not an alias), and add a DNS record for the host name pointing
   at their endpoint's IP.
3. Approve their connection, checking where it comes from:
   ```bash
   scripts/approve-private-endpoints.sh <app-gateway-resource-id> <client-subscription-id> [...]
   ```
   The script approves pending connections whose private endpoint lives in a listed subscription and
   rejects the rest. Re-run it whenever the client adds an endpoint.
4. Verify with the client: `curl -v https://<host>/healthz` from their network returns 200 and the
   certificate matches. In the client's Log Analytics, App Gateway access logs show their requests.
5. First Private Link client only: enable NSG flow logs on `snet-agw` for a day and confirm the source
   addresses are from `snet-agw-pl` (the NSG rule relies on it).

## ExpressRoute or VPN (three steps, two teams)

### Step 1: us
1. Collect from the client: the ranges their users come from (narrow, not `10.0.0.0/8`), and either the
   circuit resource ID (ExpressRoute) or their VPN device's public IP (VPN).
2. Check the ranges against P&T's IPAM. If they overlap any spoke or another client:
   - VPN: ask P&T for a `/24` (or matching size) from `100.64.0.0/10` and add a `vpn.nat` mapping.
     `on_prem_prefixes` lists the translated range.
   - ExpressRoute: the client must advertise a unique range (NAT on their edge), or switch to Private Link.
3. Set `client_connectivity` (see `clients/acme` for ExpressRoute, `clients/fabrikam` for VPN) with
   `hub.gateway_transit = false`. PR, plan, apply. CI refuses overlaps with the client's own spoke.
4. Send P&T `terraform output -json hub_connectivity_request`.

### Step 2: P&T
1. The client sends the secret straight to P&T, never through us or a ticket:
   - VPN: a pre-shared key (32+ random characters) stored as `vpn-psk-<code>`.
   - ExpressRoute: an authorization key on their circuit stored as `er-auth-<code>`.
2. P&T adds the request to their hub `clients` map with a unique `firewall_priority` and applies
   (`terraform/hub` is the reference). CI refuses overlaps between any clients, duplicate priorities,
   and more circuits than the gateway SKU links.
3. P&T sends the client `terraform output client_handout`: the two addresses to route to Azure, the
   DNS zone to forward and the forwarder IP, and for VPN the two gateway peer IPs and IPsec policy.

### Step 3: us, then the client
1. Set `hub.gateway_transit = true` for the client and apply. The plan-time warning disappears.
2. The client builds their side: two tunnels to the two VPN peer IPs (active-active), or links the
   circuit; routes for the two addresses; a conditional forwarder for their host name.
3. Verify:
   ```bash
   # Tunnel / circuit up
   az network vpn-connection show -g <hub-rg> -n con-<hub>-<code>-s2s --query connectionStatus
   az network vpn-connection show -g <hub-rg> -n con-<hub>-<code>-er  --query connectionStatus
   # What the VPN gateway tells this client (must be hub + spokes only, never another client's range)
   az network vnet-gateway list-advertised-routes -g <hub-rg> -n vpngw-<hub> --peer <client device ip>
   # Return path from the App Gateway subnet goes to the firewall
   az network nic show-effective-route-table ...   # or Network Watcher next hop from snet-agw to a client IP
   ```
   From the client's network: `nslookup <host>` returns the App Gateway IP; `curl https://<host>/healthz`
   returns 200. Hub firewall logs show the allow from `rcg-aiadv-<code>`; anything else from that client
   shows a deny.

## Offboarding
Reverse order: P&T removes the client from the hub `clients` map (connection, NAT, routes, firewall
rule, DNS zone, hub-side peering go with it) and deletes the secrets; we set `client_connectivity`
back to `none` before the stamp is destroyed. For Private Link, reject the client's endpoint
connections first. Nothing else in the hub changes, because every hub resource is keyed by client code.
