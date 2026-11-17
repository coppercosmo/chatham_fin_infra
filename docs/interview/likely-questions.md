# Likely technical questions and answers

**"Walk me through onboarding a new insurance client."**
P&T vends a subscription into our MG with a CIDR and two Entra groups. We request AOAI quota. We add
the client to the platform layer (creates their deploy and plan identities), copy the client
template folder, fill in ~30 lines, open a PR. CI plans just that client; merge applies it in its
ring. See `docs/runbooks/onboard-a-client.md`. Engineering time is under a day; elapsed time is
bounded by vending and quota.

**"Why not just one resource group per client? It's cheaper."**
Resource groups share subscription-level roles, policies, quotas, and the Activity Log. Azure OpenAI
quota is per subscription per region, so one client's batch job could throttle another. For a
financial-services client I want the boundary Azure enforces, not one my code has to get right.

**"How do private endpoints and DNS actually work here?"**
The PE gets a NIC in `snet-pe`. The service's public FQDN CNAMEs to `<name>.privatelink.<zone>`;
the hub's private DNS zone (linked via the hub resolver, which our VNet uses as DNS server) answers
with the PE's private IP. In the landing zone, P&T's deploy-if-not-exists policy creates the A
record, which is why the module ignores changes to the DNS zone group. Test: `nslookup` from the
spoke returns a 10.x address; from the internet the call is refused.

**"How do you stop the pipeline from being the weakest link?"**
OIDC, no secrets. One identity per client federated to one GitHub Environment. Apply identity can't
assign roles beyond a fixed list (ABAC condition on RBAC Administrator). PRs use a read-only plan
identity, so unreviewed code can't apply. Required reviewers on ring 1/2 environments.

**"How would you structure Terraform modules for reuse across teams?"**
Small single-purpose modules with no provider blocks, typed variables with validation, outputs
for everything consumers need. One root "stamp" composes them. Version modules by Git tag once
they're shared beyond this repo. Tests with `terraform test` and a mocked provider run in CI with
no cloud access.

**"Something broke in production for one client. What happens?"**
Blast radius is one subscription. Alerts route to the shared action group; the client's own
workspace has the logs. Example runbook: `incident-aoai-throttling.md`. Communicate impact in
business terms to the engagement lead.

**"P&T says no to something you need. What do you do?"**
Bring data and a proposal they can own (e.g., `policy/` definitions), ask for a time-boxed
exemption recorded in an ADR if it's blocking a client, and make their job easier next time with a
repeatable request. They're the long-term owner of guardrails; I want to be their best consumer.

**"How does a model upgrade (e.g., new GPT version) reach clients?"**
Deployments use `NoAutoUpgrade`. Change the version in the stamp default or a client's tfvars,
ring 0 first (our internal client runs evals), then pilots, then everyone.

## Ingress (ADR 0010)

**"Walk me through a request from a client's analyst to Azure OpenAI."**
DNS (P&T's) resolves `acme.ai.<domain>` to the App Gateway's private IP in the acme spoke. The
analyst comes in over ExpressRoute/VPN via the hub (or Front Door Private Link). App Gateway
terminates TLS with a cert it reads from acme's Key Vault using its managed identity. The WAF
inspects the request (DRS 2.1, bot rules, rate limit). App Gateway re-encrypts to the Container Apps
environment's internal IP with the app's FQDN as host header. The app gets a token as acme's managed
identity and calls Azure OpenAI through its private endpoint. Every hop is private and logged in acme's workspace.

**"Why an App Gateway per client? That's expensive."**
About USD 330/month base. In return: one client's WAF tuning or bad config can't take down another
client, certs for every client aren't readable by one identity, and WAF logs (which contain prompt
fragments) stay in the client's workspace. For a shared, low-sensitivity product I'd consider a
shared gateway with per-listener WAF policies, and say so in an ADR.

**"The WAF keeps blocking prompts. What do you do?"**
Natural language trips SQLI/XSS rules. I exclude the prompt JSON fields from those two rule groups
only, keep everything else inspecting them, and run Detection mode for a week on a new client to
tune from the logs. Prompt injection is handled in the app (Azure AI Content Safety / Prompt
Shields), not the WAF. Runbook: `waf-false-positive.md`.

**"How does App Gateway get its certificate, and what happens at renewal?"**
Versionless Key Vault secret ID, user-assigned identity with Secrets User on that vault only,
reached through the vault's private endpoint. App Gateway polls every 4 hours, so a renewed cert in
Key Vault is picked up with no deployment.

**"Anything special about LLM traffic at the gateway?"**
Response buffering off so tokens stream, backend timeout raised to 180s, body inspection up to 2 MB,
and a per-IP rate limit so a runaway script can't burn the client's AOAI quota.

## AKS (ADR 0011)

**"Would you run all clients in one AKS cluster with a namespace each?"**
No. That's soft multi-tenancy: shared kernel, control plane, cluster admins and CNI. One container
escape or one bad RoleBinding crosses clients. Node pool per client is better but still shares the
API server and admins. For client data I'd use a dedicated cluster per client in that client's
subscription, which keeps the same boundary as everything else.

**"When would you choose AKS over Container Apps?"**
Self-hosted or fine-tuned models on GPUs, Kubernetes operators or a mesh, or a client requirement.
Otherwise Container Apps, because the fixed cost and the ops load per client are much lower.

**"How do pods authenticate to Azure OpenAI?"**
Workload identity. The cluster has an OIDC issuer; the client's app managed identity has a federated
credential trusting `system:serviceaccount:advisor:advisor-api` on that issuer only. The pod gets an
Entra token, no secrets. Same identity and roles as on Container Apps.

**"The API server is private. How does CI deploy?"**
Terraform builds the cluster through ARM, which doesn't need the API server. Workloads are deployed
by Flux running inside the cluster, pulling from Git, so CI never needs network access or
credentials to the cluster. Humans get in through P&T's Bastion/jump path with Entra + PIM.

**"AGIC or Application Gateway for Containers?"**
Neither for now. AGIC lets a controller in the cluster rewrite a Terraform-owned gateway. AGC is
Microsoft's direction for AKS and I'd revisit it, but it doesn't serve Container Apps clients and
I want one WAF, cert and log pattern everywhere. So it's App Gateway WAF in front of internal managed NGINX.

**"How do P&T's guardrails reach inside the cluster?"**
The Azure Policy add-on runs Gatekeeper, so P&T's Kubernetes policy initiatives (no privileged
containers, allowed registries, required limits) are enforced in-cluster, and compliance shows up in
the same Azure Policy view they already use.

## The AI layer (RAG)

Fifteen questions on the AI side (what happens when an analyst asks a question, RAG versus fine-tuning, hybrid search, PTU, evaluations, prompt injection through documents, push versus pull indexing, agents) are answered at the end of [the AI layer deep dive](deep-dives/ai-architecture.md#interview-questions-and-answers).

## AI gateway (ADR 0012)

**"Where does an AI gateway fit, and doesn't the WAF already do this?"**
Different jobs. The WAF protects the edge from bad user traffic. The AI gateway sits behind the app
and governs model traffic: who may call which model, how many tokens per minute, which backend to
use when one is saturated, and how usage is metered. Order: users -> App Gateway WAF -> app ->
APIM AI gateway -> Azure OpenAI over private endpoints.

**"Shared APIM or one per client?"**
For client data, one per client in the client's subscription. A shared gateway processes every
client's prompts with one identity that can call every client's models, and needs network paths
into every spoke, which undoes the subscription-per-client boundary. If Platform Engineering runs a
central APIM, the compromise is a workspace with a dedicated workspace gateway per client. For
internal apps, shared is fine and cheaper.

**"How do you stop one workload draining a client's quota?"**
`llm-token-limit` per calling identity (tokens per minute, optional monthly quota), set below the
deployment's capacity so interactive traffic keeps headroom. Callers get remaining-token headers so
they can back off before a 429.

**"How do you do chargeback?"**
`llm-emit-token-metric` with Client and CallerAppId dimensions, plus the APIM LLM logs table with
prompt and completion tokens per request in the client's workspace. Monthly KQL rolls it up per
deployment and app. No prompt text is logged by default.

**"PTU and pay-as-you-go together?"**
The PTU deployment is the primary backend; pay-as-you-go (or a second region in the same data zone)
is the secondary. A 429 or 5xx fails over, and a circuit breaker keeps the saturated backend out of
rotation for a minute, honouring Retry-After. Native load-balanced pools are the cleaner version once
the Terraform provider supports them.

**"Can an app skip the gateway?"**
No. When the gateway is on, the app's identity has no role on the model accounts; only the
gateway's managed identity does. A test in CI asserts that.

**"It's in preview. Would you put it in production?"**
The core APIM AI gateway policies are what I'd rely on; the Foundry attachment and content safety
policy are preview. So: ring 0 on our internal client first, measure latency and reconcile token
numbers, then a pilot client, with explicit exit criteria before it becomes the default.

**"Semantic caching?"**
Useful for FAQ-style apps, but within a client it can hand one user's answer to another user, so
it's per client, varied by user or group, and enabled per solution after review, not by default.

## Client network connectivity (ADR 0013)

**"A client wants their analysts to reach the app privately from their own network. What are the options?"**
Four, set per client with one input. If they're already on Azure, Private Link: they create a
private endpoint in their own subscription that connects to their App Gateway, and we approve it.
If not, ExpressRoute (their circuit linked to P&T's hub gateway) or a site-to-site VPN to the hub.
Or nothing private, for internet users behind a locked-down public frontend. I lead with Private
Link because it isn't routing at all. See `docs/architecture/client-connectivity.md`.

**"What does 'Layer 3' mean when people say ExpressRoute is a Layer 3 service?"**
It's the network layer: IP addresses and routing. ExpressRoute doesn't stretch the client's LAN into
Azure (that would be Layer 2); it connects two separate IP networks with routers that exchange
routes over BGP. That's why address ranges can't overlap: a router can't send a reply to a range
that exists on both sides.

**"Why is Private Link your first choice?"**
Nothing is routed, so nothing is shared. The client's network never learns our ranges, our hub never
learns theirs, overlapping addresses don't matter, and the only thing reachable is the one frontend
the endpoint points at. Access is an approval we can see and revoke. Most banks and insurers already
have ExpressRoute into their own Azure, so their users get there over a path they already run.

**"You connect several clients to one shared hub. How do you stop client A reaching client B?"**
Layers, all generated from one list of the client's ranges so they can't drift. The GatewaySubnet
sends every spoke's traffic to the firewall. The firewall has one rule per client: its ranges to its
own App Gateway IP on 443, default deny. In the client's spoke, the App Gateway NSG and the WAF
allow-list admit only that client's ranges, never the `VirtualNetwork` tag, which would match every
network the hub gateway has learned. Replies go back through the firewall. And Terraform refuses to
plan if any ranges overlap.

**"Why is BGP off on the VPN tunnels? Isn't BGP best practice?"**
For a company's own branches, yes. On a gateway shared by competing clients, BGP passes routes learned
from one peer to all the others, so client A would learn how to reach client B's office. With static
routes the gateway has nothing to pass on. I check `list-advertised-routes` per client during onboarding.

**"Two clients both use 172.16.0.0/16 internally. Now what?"**
VPN: the hub VPN gateway does static 1:1 NAT, so one of them appears in Azure as a unique
`100.64.x.0/24` from P&T's IPAM, and every Azure-side control uses the translated range. ExpressRoute
gateways can't NAT, so that client advertises a unique range from their edge, or uses Private Link,
where overlap doesn't matter. CI catches the clash before Azure does.

**"Why the firewall in the path? The NSG already restricts it."**
Defence in depth across ownership boundaries. The firewall rule is P&T's control in their
subscription; the NSG and WAF are ours in the client's subscription. A mistake in one doesn't open
the path. The cost is that firewall routing must be symmetric, so the App Gateway subnet has a route
table sending replies to client ranges back through the firewall, with gateway propagation off.

**"What can a connected client still see that you'd rather they didn't?"**
The ExpressRoute gateway advertises every gateway-transit spoke to every circuit, so acme's routers
learn that other spoke prefixes exist, and the DNS resolver will answer other clients' host names.
Neither gives access. If a client's risk team won't accept that, Private Link removes both, or a
dedicated hub for that client as a recorded exception.

**"Who does what, given P&T owns the hub?"**
Our stamp generates `hub_connectivity_request`: spoke range, App Gateway IP, host name, client ranges,
circuit ID or VPN device IP. P&T pastes it into their hub's `clients` map, adds a firewall priority,
and applies our proposed `hub-connectivity` module. Secrets (VPN key, ExpressRoute authorization key)
go from the client straight to P&T's Key Vault, never through us. Then we flip gateway transit on.
Three applies, two teams, no retyped IPs.

**"ExpressRoute or VPN for a new client?"**
ExpressRoute if they have it or need predictable latency and an SLA; VPN for smaller clients, a fast
start, or as ExpressRoute's backup. Both share the hub gateways' bandwidth, so I'd watch per-connection
throughput, because a heavy document-upload client is a noisy neighbour.

**"Anything surprising you hit?"**
App Gateway Private Link isn't supported on the private-only App Gateway deployment, so a Private Link
gateway keeps a public IP for Azure's control plane with no listener on it. And Private Link to App
Gateway has a ~5 minute idle timeout, which matters for long LLM calls: clients need TCP keepalives.

## Compliance standards (ADR 0016)

Full answers, with the control mapping and per-tier queries, in
[compliance-standards.md](../architecture/compliance-standards.md#interview-questions-and-answers).

**"Which Defender for Cloud compliance standards would this platform use?"**
MCSB from P&T's root; SOC 2 Type 2, ISO 27001:2022 and NIST 800-53 Rev. 5 assigned once at the AI Advisory
management group, report-only; DORA, NIST CSF 2.0, UK OFFICIAL or NCSC CAF per client at the client's scope.
The EU AI Act and NIST AI RMF are built in but have 6 and 1 checks. NYDFS Part 500 and ISO 42001 aren't in
Defender at all.

**"How does that work when clients share a cell?"**
Defender reports per subscription, which is one client only in Tier 1. In a cell I filter Azure Policy
compliance to the client's resource group plus the shared resources, using the `client` tag the guardrails
enforce, and assign a client-specific standard at its resource group.

**"What's the catch with the dashboard?"**
It covers the automated part of each framework only, and it scores the built-in checks, not our own deny
rules. Turned on today, customer-managed keys would fail under SOC 2, NIST and DORA (a known gap, which MCSB
hides because its CMK checks are off by default), so I'd record that as a dated exemption with an ADR.
