# ADR 0014: Isolation tiers (dedicated, shared cell, pooled)

- Status: Proposed, amends 0001 (and, for Tiers 2 and 3 only, 0006 and 0012); ingestion amended by 0015
- Date: 2026-11-16
- Plain-words version with diagrams and cost math: [isolation-tiers.md](../architecture/isolation-tiers.md)

## Context
ADR 0001 gives every client its own subscription (a "stamp"). It is the strongest boundary Azure
offers short of a separate tenant, and it stays the default for confidential client work. But every
stamp pays for its own front door, AI gateway, search service and always-on compute, whether the
client sends one request a day or ten thousand:

| Per Tier 1 client, USD/month (approx. list price) | Pilot SKUs | Production SKUs |
|---|---|---|
| App Gateway WAF_v2 (ADR 0010) | ~400 | ~400 |
| AI gateway, APIM (ADR 0012) | ~50 (Developer) | ~700 (Standard v2, to validate) or ~2,800 (Premium) |
| AI Search | ~75 (Basic) | ~245 (S1) |
| Private endpoints (6), logs, an always-on replica, vault, storage | ~175 | ~175 |
| **Total before tokens** | **~700** | **~1,500 (~3,600 with Premium)** |

At 200 clients that is roughly USD 300k/month of mostly idle infrastructure on production SKUs, and
every onboarding waits on P&T's subscription vending. Much of the pipeline doesn't need that: trials,
internal Chatham tools, standard-content products over Chatham's own research, and smaller clients whose
data is classified internal.

The question is not "can it be cheaper" (it obviously can) but **"what is the cheapest design where
isolation is still enforced by Azure, not by our application code being bug-free?"**

The observation that drives the answer: the expensive parts (App Gateway, APIM, search units,
always-on replicas) are **stateless** and priced per instance. The parts that **store client data**
(storage account, Key Vault, search index, Azure OpenAI account, Log Analytics workspace) are cheap or
free per instance. So share the first group and keep the second dedicated.

## Options considered

| Option | Isolation (enforced by) | Cost at 200 clients | Verdict |
|---|---|---|---|
| A. Tier 1 for everyone (ADR 0001 as is) | Subscription: RBAC, Policy, quota, network, logs, cost | ~USD 300k/month | Keep for the clients who need it |
| B. Resource group per client, each with a full stack, in a shared subscription | Resource group RBAC | Barely cheaper: same gateways and search per client | Rejected: weaker and not cheaper |
| **C. Shared cell**: shared edge, compute and AI gateway; per-client data, keys, models, identities and logs in per-client resource groups | Per-client managed identities and resource-scoped RBAC; keys disabled everywhere | ~USD 170 per client | **Chosen as Tier 2** |
| **D. Pooled app**: one app for many tenants; tenant from a signed token claim; tenant data in per-tenant containers and indexes; the app itself has no data role | Azure RBAC at container and index scope, checked against the signed-in user's own token | ~USD 45 per tenant | **Chosen as Tier 3**, low-sensitivity data only |
| E. Pooled app with one shared index and a tenant filter in every query | Application code only | Lowest | Rejected: one missing filter leaks every tenant |
| F. One APIM with workspaces and a dedicated workspace gateway per client | Per-client gateway runtime, shared management plane | Per-gateway cost | Possible later variant of Tier 2's gateway; not needed to start |
| G. AKS with a namespace per client | Kubernetes RBAC and network policy | Cluster cost amortised | Rejected: more to run, and a weaker boundary than separate Container Apps with separate identities |

## Decision
Three tiers, built from the same modules and running **the same application image**. The image reads
`TENANCY_MODE` (`single` or `pooled`) and nothing else differs in code.

| | Tier 1: Dedicated | Tier 2: Shared cell | Tier 3: Pooled |
|---|---|---|---|
| Terraform root | `stamps/client` | `stamps/cell` + `stamps/cell-client` | `stamps/pool` |
| Boundary | Subscription | Resource group + identities, inside a cell subscription (≤ 20 clients) | Sub-resources + token claim, inside a pool subscription (≤ 45 tenants) |
| Shared | Nothing (P&T hub only) | VNet, App Gateway, Container Apps environment, APIM, search service, TLS vault | Everything except the per-tenant pieces |
| Dedicated | Everything | Storage, Key Vault, search **index**, Azure OpenAI account, Log Analytics, App Insights, app, gateway and ingestion identities, deployment identity, budget | Blob container + encryption scope, search index, Entra group, ingestion job identity, token limit |
| Data classification allowed | Up to highly confidential | Up to confidential | Public and internal only (validated in Terraform) |
| Cost before tokens | ~1,500 (~3,600 with Premium APIM) | ~170 at 20 clients (~280 with Premium APIM) | ~45 at 45 tenants (~90 with Premium APIM) |
| Onboarding | Days to weeks elapsed (vending, peering, quota) | Hours: three pull requests, no vending | Same day: a map entry and a P&T group |

### Tier 2: shared cell (Azure Architecture Center calls this "horizontally partitioned")
1. **Per-client data plane.** Each client's storage, vault, Azure OpenAI account, workspace and search
   index are separate resources in `rg-<client>-<env>-<region>`. Keys are disabled on all of them
   (ADR 0004), so the only way in is a token for an identity with a role on that resource.
2. **Per-client identities.** `id-<client>-app` has data roles on that client's storage, vault and
   index only. `id-<client>-gw` has `Cognitive Services OpenAI User` on that client's Azure OpenAI
   account only. `id-<client>-ingest` (ADR 0015) reads that client's documents and writes its index.
   All three live in the client's resource group.
3. **Shared APIM, per-client API.** Each client's API validates that the caller is that client's app
   or ingestion identity (`client-application-ids`) and calls Azure OpenAI with
   `authentication-managed-identity client-id="<that client's gateway identity>"`. APIM holds every
   gateway identity, but each API can only use its own; the rendered policies are asserted in tests.
4. **Shared App Gateway, per-client site.** One listener, certificate and WAF policy per host name;
   two clients can't share a host name (validated).
5. **Shared Container Apps environment, per-client app.** Each app runs as its own client's identity
   and accepts ingress only from the App Gateway subnet, so apps can't call each other.
6. **Per-client deployment identity.** The cell creates each client's resource group (`client_slots`)
   and gives that client's pipeline identity Contributor there, an RBAC Administrator role limited by
   condition to the seven roles `cell-client` assigns, a locks-only custom role, and a join-only custom
   role on the cell's endpoint subnet (and DNS zones when standalone). It has no rights on the cell's
   shared resources or on another client's resource group.
7. **Cell deployment identity holds no data roles.** The only data roles the cell grants are on a
   client's own search index: write for that client's ingestion identity and read for its app (or
   write for the app, if the client has no ingestion job). The cell's index admin identity manages
   index definitions but can't read documents (ADR 0015).
8. **Capacity.** Azure OpenAI quota is per subscription and region, so a cell's clients draw from one
   regional quota at deployment time. Capacity assigned to a deployment is a hard partition at run
   time, so one client can't use another's. PTU is Tier 1 only (validated).

### Tier 3: pooled
1. **Tenant from the token, never from input.** P&T owns the app registration; each tenant's Entra
   group is assigned the app role `Tenant.<code>`. App and gateway read the tenant from that claim.
2. **The pooled app's identity has no data role.** It reads tenant data **with the signed-in user's
   token** (on-behalf-of), and Azure checks the user's tenant group at container scope
   (`Storage Blob Data Reader`) and index scope (`Search Index Data Reader`) on every call. A bug that
   asks for another tenant's container is refused by Azure, not by our code.
3. **Background work runs per tenant.** Ingestion has no user, so each tenant has its own job and
   `id-<tenant>-ingest` identity with rights on that tenant's container and index only. Push-only
   indexing, because search indexers bypass index-scoped RBAC.
4. **Per-tenant encryption scope** on the storage account (optionally a customer-managed key per
   tenant, which allows crypto-shredding at offboarding).
5. **Per-tenant fairness** at the gateway: token limit and quota keyed by tenant, plus a `Tenant`
   metric dimension for showback.
6. **Stateless model use only**: no stored completions, Assistants threads, files or vector stores
   in the shared Azure OpenAI account. No shared semantic cache; app caches keyed by tenant and user.

### Same in every tier
Private endpoints only, keyless authentication, data-zone deployments, the P&T policy initiative
(`modules/policy-guardrails`), tags (`client`/`cell`/`pool`, `isolation_tier`, `data_classification`),
ring-based rollout (ADR 0008), and the egress path through P&T's firewall.

### Assigning a tier
Tier 1 if **any** of: highly confidential or regulator-named data; a contract that requires a
dedicated subscription, network or customer-managed keys on everything; PTU or a client-specific
model; AKS or GPUs. Tier 3 only if **all** of: data is public or internal; no client-specific model;
the contract accepts logical isolation. Everything else is Tier 2. The engagement lead and Chatham's
risk team sign the choice; it is recorded in the client's config (`isolation_tier` tag).

Promotion (Tier 3 to 2 to 1) is a new environment plus a data copy and a DNS cut-over, never an
in-place change of boundary. Demotion needs the same sign-off as the original choice.

## Consequences
- Fixed cost per client drops roughly 9x in Tier 2 and 30x in Tier 3. An illustrative 200-client mix
  (20 / 120 / 60) is ~USD 55k/month instead of ~300k (see the design doc for the math).
- Onboarding to Tier 2 or 3 doesn't wait for subscription vending, peering or a quota request.
- **Weaker than Tier 1, and we say so first:** Tier 2 clients share a network, a front-door IP and
  the Microsoft-managed compute environment, and draw from one regional model quota. A
  misconfiguration of a shared component affects every client in the cell (blast radius: 20).
  Tier 3 tenants share a process, a quota and an outage domain; a cache or memory bug in our code
  could mix answers, which is why Tier 3 is limited to public and internal data.
- Three Terraform roots to maintain instead of one. Mitigated by shared modules, the same app image,
  and tests that assert the isolation rules for every entry in every map.
- Platform limits become design limits: App Gateway listeners, APIM APIs, AI Search indexes per
  service (S1: 50, hence the pool cap of 45), role assignments per subscription (4,000). Cells and
  pools are capped well below them; a full cell or pool means a new one, not a bigger one.

## Open questions (for P&T and Chatham risk)
- Will client contracts and vendor-risk questionnaires accept Tier 2 for confidential data? Draft
  answer: "dedicated data stores, keys, model account, logs and identities; shared Microsoft-managed
  compute and network edge" (in the design doc's Q&A).
- Does P&T allow the two narrow custom roles at the cell resource-group scope, or prefer to own
  them at the management group?
- Standard v2 APIM for cells and pools (ADR 0012 already flags it to validate): it changes the
  per-client cost of Tiers 2 and 3 more than anything else.
