# Runbook: onboard a new client

A client can be hosted three ways ([ADR 0014](../adr/0014-isolation-tiers.md), explained in plain words in
[isolation-tiers.md](../architecture/isolation-tiers.md)). Pick the tier first, because every later step
depends on it, then follow that tier's section.

| | Tier 1: dedicated | Tier 2: shared cell | Tier 3: pooled |
|---|---|---|---|
| Isolation boundary | The client's own subscription | The client's own resource group and identities, in a cell subscription shared by up to 20 clients | The tenant's own container, index and Entra group, in a pool subscription shared by up to 45 tenants |
| Data allowed | Up to highly confidential | Internal or confidential | Public or internal |
| What we ask P&T for | Subscription, a /22 from IPAM, Entra groups, hub peering, DNS, firewall rules | Entra groups, a certificate, a DNS record, and a firewall rule for a routed client | One Entra group and its `Tenant.<code>` app role |
| Our pull requests | Platform layer, then `terraform/clients/<client>/` | Cell (slot), then client (`cells/<cell>/clients/<client>.tfvars`), then cell (wiring) | One entry in `terraform/pools/<pool>/terraform.tfvars` |
| Terraform root | `stamps/client` | `stamps/cell` and `stamps/cell-client` | `stamps/pool` |
| Model capacity | A quota request per client | The client's own deployments, from the cell's regional quota | The pool's shared deployments |
| Time | Under a day of engineering; days to weeks elapsed (vending, peering, quota) | Hours; no vending | Same day |

## 0. Pick the tier
- [ ] **Tier 1** if **any** of these is true: highly confidential or regulator-named data; a contract that
      requires a dedicated subscription, a dedicated network or customer-managed keys on everything; PTU or a
      client-specific model; AKS or GPUs.
- [ ] **Tier 3** only if **all** of these are true: the data is public or internal; no client-specific model;
      the contract accepts logical isolation.
- [ ] Everything else is **Tier 2**.
- [ ] The engagement lead and Chatham's risk team sign the choice. Terraform records it on every resource as
      the `isolation_tier` tag.
- [ ] Moving a client up later (3 to 2 to 1) means a new environment, a data copy and a DNS cut-over, never an
      in-place change of boundary. Moving down needs the same sign-off as the original choice.

P&T owns the guardrails in every tier: management groups, policy, Entra groups and app registrations, the
hub, DNS, the firewall and IPAM (ADR 0002). The steps below only ever *ask* for those; no tier needs us to
create a group, a policy or a hub resource ourselves.

---

## Tier 1: dedicated subscription

Target: from "contract signed" to "app reachable" in **under a day of engineering time** (elapsed time
depends on P&T vending and AOAI quota). Example: `terraform/clients/acme`.

### 1. Request from P&T (standard template)
- [ ] Subscription in `AI Advisory / Clients` MG, name `sub-aiadv-<client>-prd`
- [ ] Spoke CIDR from IPAM (default /22)
- [ ] Entra groups: `sg-aiadv-<client>-readers`, `sg-aiadv-<client>-operators` (PIM-eligible)
- [ ] Budget owner and cost center
- [ ] Hub peering accepted on the hub side, firewall rules for required egress

### 1b. Ingress prerequisites (ADR 0010)
- [ ] Host name `<client>.ai.<domain>` and its certificate (from P&T's CA process or Key Vault's
      integrated CA); import it into the client vault after the first apply, then set the
      versionless secret ID in `ingress.certificate_secret_id`
- [ ] Decide `frontend_mode`: private (default) or public with the client's egress CIDRs
- [ ] P&T: DNS record to the gateway's private IP (`x.x.2.10`) or Front Door Private Link setup
- [ ] Subscription feature for private-only App Gateway deployment registered (vending template)

### 1c. AKS only (ADR 0011)
- [ ] Written reason for AKS in the client config (GPU, operators, client requirement)
- [ ] P&T: `sg-aiadv-<client>-aks-admins` group (PIM-eligible)
- [ ] P&T: `Private DNS Zone Contributor` on `privatelink.<region>.azmk8s.io` for the cluster's
      control-plane identity (output after a targeted apply of the identity)
- [ ] GPU quota in the region if `aks.gpu_pool` is set
- [ ] Flux configuration pointing at the client's rendered `kubernetes/` overlay

### 1d. AI gateway (ADR 0012)
- [ ] Decide SKU (Developer for pilots, Premium or Standard v2 for production) and token limits
- [ ] Decide prompt/response body logging with the engagement lead (default off)
- [ ] P&T: link the `<apim>.azure-api.net` private DNS zone to the hub resolver VNet (landing zone)

### 1e. Client network (ADR 0013)
- [ ] Ask the client: are you on Azure already? If yes, plan on `privatelink` (no hub work, no IP planning)
- [ ] Otherwise `expressroute` (they have a circuit) or `vpn`; collect their user ranges, VPN device IP or
      circuit ID, and check the ranges against IPAM. Overlap means NAT (VPN) or a unique advertised range (ExpressRoute)
- [ ] Follow [connect-client-network.md](connect-client-network.md) for the three-step hub handover

### 1f. Documents and ingestion (ADR 0015)
- [ ] Push (default) or pull? Pull (an AI Search indexer) is Tier 1 only, needs the client's OK that
      embedding calls skip the AI gateway, and adds two shared private links the pipeline approves
- [ ] Ingestion image digest for `ingestion.image` (same release as the app, promoted by ring)
- [ ] Container for documents (default `documents`) and the schedule (default 02:00 UTC, off-peak)
- [ ] Make sure `model_deployments` has the embedding deployment (`embeddings` by default)
- [ ] AKS clients: apply `kubernetes/ingest-cronjob.yaml` with the values from `terraform output ingestion`

### 1g. Compliance standards (ADR 0016)
- [ ] Does the contract or the client's regulator name a standard beyond SOC 2, ISO 27001 and NIST 800-53
      (inherited from the AI Advisory MG)? For example DORA (EU), NIST CSF 2.0 (US banks), UK OFFICIAL or NCSC CAF
- [ ] If yes, add it to `scoped_standards` in P&T's `compliance-standards` config at the client's subscription,
      in the same pull request as the onboarding
- [ ] Decide with the client whether Defender may keep suspicious prompt evidence in AI alerts (default off)

### 2. Request quota
- [ ] Azure OpenAI quota for each model in `terraform.tfvars` in the target region and SKU
- [ ] Note any data-residency or abuse-monitoring requirements from the client contract

### 3. Add the client to the platform layer
- [ ] Add the client to `terraform/platform/terraform.tfvars` `clients` map (creates
      `id-deploy-<client>`, the federated credential, and its constrained role assignment)
- [ ] PR, review, apply `platform`

### 4. Add the client config
- [ ] `cp -r terraform/clients/_template terraform/clients/<client>` and fill in values
- [ ] Create GitHub Environment `client-<client>` with variable `AZURE_CLIENT_ID`
      (output of step 3) and set reviewers for its ring
- [ ] Open a PR: CI plans only this client. Review the plan, merge, ring rollout applies it

### 5. Verify
- [ ] `nslookup <oai>.openai.azure.com` from inside the spoke resolves to a `10.x` address
- [ ] Calling any client endpoint from the internet fails (public access disabled)
- [ ] App health endpoint returns 200 through P&T ingress
- [ ] Logs visible in the client workspace; client appears in the central workbook
- [ ] Budget alert recipients confirmed
- [ ] Pull mode only: both shared private links show Approved
      (`az search shared-private-link-resource list --service-name <srch> -g <rg> -o table`); the apply
      workflow approves them, and any it skipped are listed in its log
- [ ] First ingestion run: `az containerapp job start -n job-<client>-ingest -g <rg>`, then check the
      execution succeeded and the index has documents
- [ ] Ask a question whose answer is in a known document and check the citation

---

## Tier 2: shared cell

The client gets its own resource group inside a cell subscription that P&T vended once. Its storage, Key
Vault, Azure OpenAI account, Log Analytics workspace, App Insights, identities and budget are its own. The
VNet, App Gateway, Container Apps environment, API Management and AI Search service are the cell's, and the
client gets its own site, app, API and index on them. Three pull requests, no subscription vending.
Example: `terraform/cells/cell01` (`10.110.0.0/22`) with northwind, tailspin and litware.

Names below use the naming module's pattern: `rg-<client>-prd-<region>` for the client's resource group,
`rg-<cell>-prd-<region>` for the cell's shared one (`rg-northwind-prd-eus2` and `rg-cell01-prd-eus2` in the
example).

### Step 1. Check the client fits the cell
- [ ] The cell has room: fewer than `max_clients` (20) entries in `client_slots`. If it's full, open the next
      cell ([below](#opening-a-new-cell-or-pool)); never raise the cap, because a cell is the blast radius of a
      bad change.
- [ ] The client needs nothing that is Tier 1 only: PTU (`cell-client` refuses it), AKS, pull ingestion (an
      AI Search indexer), prompt and response bodies in the gateway logs (the shared gateway never logs
      bodies), or customer-managed keys on everything.
- [ ] The cell's regional Azure OpenAI quota has room for the client's `model_deployments`:
      `az cognitiveservices usage list -l <region> --subscription <cell subscription id> -o table`. A cell's
      clients share one regional quota when deploying; once a deployment has capacity, no other client can use
      it. Ask for more quota on the cell subscription only if it's short.

### Step 2. Request from P&T (no subscription, IPAM range or peering: the cell has them)
- [ ] Entra groups `sg-aiadv-<client>-readers` (Reader on the client's resource group, through
      `reader_group_object_id`) and `sg-aiadv-<client>-operators` (PIM-eligible)
- [ ] Budget owner and cost center
- [ ] Certificate for `<client>.ai.<domain>` from P&T's CA process. It goes into the **cell's** vault
      (`kv-<cell>-...`), named `<client>-ai-tls`, because the shared App Gateway reads every site's
      certificate from there. Import it before step 6.
- [ ] Compliance (ADR 0016): if the contract or the client's regulator names a standard beyond SOC 2,
      ISO 27001 and NIST 800-53, add it to `scoped_standards` in P&T's `compliance-standards` config at the
      client's **resource group** (`/subscriptions/<cell subscription id>/resourceGroups/rg-<client>-prd-<region>`),
      in the same pull request as the onboarding. It shows in Azure Policy and Resource Graph, not as a
      Defender standard, and the cell's shared resources count toward it
      ([compliance-standards.md](../architecture/compliance-standards.md))
- [ ] Decide with the client whether Defender may keep suspicious prompt evidence in AI alerts (default off)

The DNS record and, for a routed client, the firewall rule come later (step 7), from the cell's output.

### Step 3. The client's deployment identity
- [ ] `id-deploy-<client>`, federated to GitHub Environment `client-<client>`, with its own state container
      `tfstate-<client>` and the AcrPull-only delegation on the platform registry, as for Tier 1
- [ ] **No role on the cell subscription.** All its rights in the cell come from the cell's `client_slots`
      (next step) and stop at the client's resource group. Don't add a cell client to `terraform/platform`'s
      `clients` map with the cell's subscription ID: that map gives Contributor on the whole subscription,
      which would reach every client in the cell (see [known gaps](#known-gaps-for-tiers-2-and-3))
- [ ] GitHub Environment `client-<client>` with variable `AZURE_CLIENT_ID` and required reviewers

### Step 4. Pull request 1, cell: give the client a slot
- [ ] Add the client to `client_slots` in `terraform/cells/<cell>/terraform.tfvars`:
  ```hcl
  client_slots = {
    # ...existing clients
    <client> = {
      deployer_principal_id = "<principal ID of id-deploy-<client>>"
      cost_center           = "AI-ADVISORY-<CLIENT>"
      owner_email           = "<client>-engagement@example.com"
      data_classification   = "confidential" # or "internal"; highly confidential is Tier 1
    }
  }
  ```
- [ ] PR (CI runs the cell tests and type-checks the config), review, apply `stamps/cell` with the cell's
      deployment identity. It creates `rg-<client>-prd-<region>` with the tags P&T's policy requires and gives
      the client's identity, on that resource group only: Contributor; Role Based Access Control
      Administrator, limited by an ABAC condition to the seven roles `cell-client` assigns; a custom role for
      delete locks; and a join-only custom role on the cell's `snet-pe` (plus its DNS zones in a standalone
      cell). Nothing on the cell's shared resources or on another client's resource group.
- [ ] Validation refuses a full cell, highly confidential data, and a deployment identity another client
      already uses.
- [ ] Note `terraform output client_resource_groups` and `terraform output -json cell_inputs_for_clients`.

### Step 5. Pull request 2, client: build the client's data stores
- [ ] Copy an existing cell client's two files, for example `cells/cell01/clients/northwind.tfvars` and
      `northwind.backend.hcl`, to `cells/<cell>/clients/<client>.tfvars` and `<client>.backend.hcl`, and set:
  - `client`, `location`, `subscription_id` (the **cell's**), and `data_classification` (the same as the slot)
  - `cell`: `name`, `pe_subnet_id` and `search_service_id` from `cell_inputs_for_clients`
    (`private_dns_zone_ids` too, for a standalone cell only), and `deployer_principal_id` set to the
    **cell's** deployment identity. `cell-client` gives that identity Managed Identity Operator on the
    client's three identities so the cell can attach them to the app, the ingestion job and the shared
    gateway; the role grants no access to anything those identities can reach
  - `model_deployments`: the chat model and `embeddings`, Standard or DataZoneStandard (PTU is refused)
  - `reader_group_object_id`, `acr`, `cost_center`, `owner_email`, `budget_contact_emails`, `monthly_budget_usd`
  - Backend: `container_name = "tfstate-<client>"`, `key = "<client>.tfstate"`
- [ ] PR, review, apply `stamps/cell-client` as `id-deploy-<client>`. It builds, in the client's resource
      group: Key Vault; storage with a `documents` container; the Azure OpenAI account with its deployments
      and the `rag-default` content filter; Log Analytics and App Insights; private endpoints in the cell's
      `snet-pe`; three identities (`id-<client>-prd-<region>-app`, `-gw` and `-ingest`); delete locks on the
      vault, storage and model account; and the budget. Keys are disabled on every data store, so a token for
      one of the client's identities is the only way in.
- [ ] `terraform output -json cell_registration`: twelve values (the three identities' IDs, the endpoints and
      the App Insights connection string), no secrets. They are the input to the next pull request.

### Step 6. Pull request 3, cell: wire the client into the shared services
- [ ] The certificate from step 2 is in the cell's vault (the App Gateway can't add the site without it).
- [ ] Add the client to `clients` in `terraform/cells/<cell>/terraform.tfvars`: the `cell_registration`
      values pasted as they are, plus:
  - `host_name` and `certificate_secret_id` (the versionless secret ID in the cell's vault)
  - `app_image`: the current app release, pinned by digest. It is set per client, so a release can reach one
    client in the cell before the others
  - `frontend`: `private` (default), or `public` with the client's egress ranges in `allowed_client_cidrs`
  - `on_prem_prefixes`: the client's ranges, for a client routed through P&T's hub (ExpressRoute or VPN)
  - `tokens_per_minute` (default 50,000; keep it at or below the chat deployment's capacity, where capacity
    40 means 40,000 tokens a minute) and `monthly_token_quota` (0 means none)
  - `min_replicas = 0` to scale the app to zero between uses (about USD 40 a month less, at the cost of a
    cold start), and `waf_mode`, `rate_limit_per_minute` or `ingest_schedule` if the defaults don't fit
  - Leave out the three `ingest_identity_*` values only if the client has no ingestion job; the app then
    writes its own index (litware in the example)
- [ ] PR, review, apply `stamps/cell`. It adds: the client's App Gateway site (listener, certificate and its
      own WAF policy); `ca-<client>`, running as the client's app identity and accepting traffic from the App
      Gateway subnet only; an API at `/<client>/openai` on the shared API Management that admits only the
      client's app and ingestion identities and calls the client's Azure OpenAI account as the client's
      gateway identity; `Search Index Data Reader` for the app and `Search Index Data Contributor` for the
      ingestion identity on index `<client>`; and `job-<client>-ingest`.
- [ ] The plan refuses: a client without a slot, a host name or identity another client uses, routed ranges
      that overlap the cell or another routed client, and a 21st client.
- [ ] Read the client's rendered gateway policy and check it names only this client's identities:
      `terraform output -json gateway_policies | jq -r '.<client>'`. The cell tests assert this for every
      client; this is the human check.
- [ ] Start the cell's index admin job once, so the client's index exists before its first ingestion run:
      `az containerapp job start -n job-index-admin -g rg-<cell>-prd-<region>`

### Step 7. P&T handover and the client's network
- [ ] Send P&T `terraform output -json hub_connectivity_request` from the cell: a DNS record for the host
      name pointing at the cell's App Gateway IP (`x.x.2.10`, so `10.110.2.10` in cell01), and for a routed
      client a firewall rule from its `on_prem_prefixes` to that IP on 443.
- [ ] ExpressRoute or VPN: check the client's ranges against IPAM as in
      [connect-client-network.md](connect-client-network.md) step 1, then follow its steps 2 and 3. Two cell
      differences: the cell's output has no circuit ID or VPN device IP, so add those to the hub request; and
      `hub.gateway_transit` is set once for the whole cell, not per client.
- [ ] Private Link, for a client already on Azure: the cell needs `enable_private_link = true` (one setting
      for the whole cell). Give the client the cell App Gateway's resource ID
      (`az network application-gateway show -g rg-<cell>-prd-<region> -n agw-<cell>-prd-<region> --query id -o tsv`)
      and the sub-resource `private`. Approve their endpoint with
      `scripts/approve-private-endpoints.sh <app gateway id> <subscription> [<subscription> ...]`, listing the
      subscriptions of **every** Private Link client in the cell: the script rejects any pending connection
      from a subscription that isn't listed, so a run with one client's subscription would reject another
      cell client's endpoint.

### Step 8. Verify
- [ ] `nslookup <oai>.openai.azure.com` from inside the cell VNet resolves to an address in the cell's `snet-pe`
- [ ] Calling the client's storage, vault or Azure OpenAI endpoint from the internet fails (public access off)
- [ ] The client's identities reach only the client's resources:
      `az role assignment list --assignee <app identity principal id> --all -o table`, in the cell
      subscription, shows scopes in `rg-<client>-prd-<region>` and the index `<client>` (`.../indexes/<client>`)
      and nothing else (AcrPull on the platform registry is in the platform subscription). Repeat for the
      gateway and ingestion identities
- [ ] The app's health endpoint returns 200 through the cell's App Gateway, from the client's network
- [ ] Logs: the app's telemetry and the model account's logs are in the client's own workspace
      (`log-<client>-prd-<region>`). App Gateway, API Management and container console logs are in the cell's
      workspace, without prompt or response bodies; check the app doesn't print prompts or document text to
      its console
- [ ] Budget alert recipients confirmed
- [ ] First ingestion run, after `job-index-admin` (step 6): the jobs live in the cell's resource group and
      run as the client's identity. `az containerapp job start -n job-<client>-ingest -g rg-<cell>-prd-<region>`,
      then check the execution succeeded and the index has documents
- [ ] Ask a question whose answer is in a known document and check the citation

---

## Tier 3: pooled

The tenant shares one app, one Azure OpenAI account, one storage account and one AI Search service with the
pool's other tenants. What is its own: a blob container with its own encryption scope, a search index, an
Entra group, an ingestion identity and job, and a token limit at the gateway. The pooled app has no data
role: it reads with the signed-in user's token, so Azure checks the user's tenant group on every read. One
pull request and one P&T request. Example: `terraform/pools/pool01` (`10.120.0.0/22`,
`advisor.ai.chatham.example.com`) with contoso, adatum, proseware and chatham.

### Step 1. Check the tenant fits the pool
- [ ] All three Tier 3 conditions in step 0 hold. Terraform refuses `confidential`.
- [ ] The tenant needs none of these, which the pool doesn't have per tenant (otherwise Tier 2): its own model
      or a token limit different from the pool's; its own network path (ExpressRoute, VPN or Private Link); its
      own budget, workspace or compliance report; a standard of its own.
- [ ] The pool has room: fewer than `max_tenants` (45; AI Search S1 allows 50 indexes per service). If it's
      full, open the next pool ([below](#opening-a-new-cell-or-pool)).
- [ ] The pool's model deployments can take the tenant's expected use. Tenants share the pool's capacity,
      and the per-tenant gateway limit (`tokens_per_minute_per_tenant`, `monthly_token_quota_per_tenant`, the
      same for every tenant) is the only fairness control. There is no quota request per tenant.

### Step 2. Request from P&T
- [ ] Entra group `sg-aiadv-<tenant>-users`. It is the tenant's data permission as well as its sign-in:
      everyone in it can read the tenant's documents, so membership is managed like access to data.
- [ ] App role `Tenant.<tenant>` on the pooled app's registration (`api://ai-advisory-pooled` in pool01),
      assigned to that group. The app and the gateway take the tenant only from this role in the user's
      token, never from a header or the URL.
- [ ] Nothing else: no subscription, IPAM range, certificate, DNS record or firewall rule. Every tenant uses
      the pool's host name.

### Step 3. Pull request, pool: add the tenant
- [ ] Add one entry to `tenants` in `terraform/pools/<pool>/terraform.tfvars`:
  ```hcl
  tenants = {
    # ...existing tenants
    <tenant> = {
      users_group_object_id = "<object ID of sg-aiadv-<tenant>-users>"
      data_classification   = "internal" # or "public"; Terraform refuses anything else
      # ingest_schedule     = "0 2 * * *"
    }
  }
  ```
- [ ] PR (CI runs the pool tests and type-checks the config), review, apply `stamps/pool` with the pool's
      deployment identity. It creates: container `<tenant>`, with encryption scope `<tenant>` enforced as its
      default; `Storage Blob Data Reader` on that container and `Search Index Data Reader` on index `<tenant>`
      for the group; `id-<pool>-prd-<region>-<tenant>-ingest`, with write on that container and index only;
      `job-<tenant>-ingest`; and the gateway's mapping from that identity to the tenant, for limits and
      metering.
- [ ] Validation refuses confidential data, a group another tenant already uses, and a 46th tenant.
- [ ] Send P&T `terraform output -json app_registration_setup_for_pt` to check their app roles and group
      assignments match the tenants map.
- [ ] Keep `terraform output -json tenants` (container, index, encryption scope, ingestion identity, group)
      with the onboarding record.

### Step 4. Index and documents
- [ ] Start the pool's index admin job once, so the tenant's index exists:
      `az containerapp job start -n job-index-admin -g rg-<pool>-prd-<region>`
- [ ] Documents go into container `<tenant>`, not `documents`. The tenant's users and the pooled app can only
      read it; of the identities the pool creates, only the tenant's ingestion identity can write to it.
- [ ] First ingestion run: `az containerapp job start -n job-<tenant>-ingest -g rg-<pool>-prd-<region>`, then
      check the execution succeeded and the index has documents

### Step 5. Verify
- [ ] Sign in at the pool's host name as a test user in `sg-aiadv-<tenant>-users`. Their token for the pooled
      app's API carries the app role `Tenant.<tenant>` and no other `Tenant.` role (decode it, for example at
      jwt.ms)
- [ ] Isolation, as that test user from inside the network:
      `az storage blob list --account-name <pool storage account> -c <tenant> --auth-mode login -o table`
      works, and the same command with another tenant's container fails with `AuthorizationPermissionMismatch`
- [ ] The pooled app still has no data role: `terraform output app_identity_roles` lists `metrics` and `acr` only
- [ ] Only the tenant's group and ingestion identity have roles on its container:
      `az role assignment list --scope <storage account id>/blobServices/default/containers/<tenant> -o table`
- [ ] Ask a question whose answer is in one of the tenant's documents and check the citation; ask one whose
      answer is only in another tenant's documents and check the app doesn't find it
- [ ] After the first questions, the gateway's token metric shows the tenant in its `Tenant` dimension
      (showback; there's no per-tenant budget)

---

## Opening a new cell or pool

Once per cell or pool, before its first client: when every cell or pool in the region is full, or a client
needs a region that has none. A cell or pool is one subscription, vended by P&T like a Tier 1 client's.

- [ ] P&T: a subscription in `AI Advisory / Clients`, a /22 from IPAM (cell01 uses `10.110.0.0/22` and pool01
      `10.120.0.0/22`), hub peering, and the AI gateway's `<apim>.azure-api.net` private DNS zone linked to the
      hub resolver VNet, as in Tier 1
- [ ] A deployment identity for the cell or pool. Adding `<code> = { subscription_id = "<its subscription id>" }`
      to `terraform/platform`'s `clients` map creates `id-deploy-<code>`, its federation to GitHub Environment
      `client-<code>`, and state container `tfstate-<code>`, which the cell's and pool's `backend.hcl` already
      expect. That is enough for a pool: every role the pool assigns is on that identity's allowed list. A
      cell's identity needs more: it creates two custom roles (data locks and private endpoint join), which
      Contributor can't, and assigns Contributor and the conditioned RBAC Administrator role on each client's
      resource group, which the Tier 1 condition doesn't allow. Whether P&T grants that at the cell, or owns
      those roles at the management group, is an open question in ADR 0014
- [ ] Copy `terraform/cells/cell01/` or `terraform/pools/pool01/` and set the code, subscription, address
      space, hub, `ai_gateway_sku` (`Premium_1` for production: the internal VNet mode needs Developer or
      Premium today), `ingest_image` and `acr`. For a cell, set `enable_private_link` if any client will connect
      from its own Azure subscription. A new cell has no App Gateway until its first client is wired in (Tier 2 step 6)
- [ ] Pool only: P&T registers the pooled app's API (`app_api_audience`) and its web front end
      (`user_token_client_app_ids`), and trusts the pool app's managed identity as a federated credential so
      the app can use on-behalf-of with no secret (`terraform output -json app_registration_setup_for_pt`).
      The host name's certificate goes in the pool's vault (`certificate_secret_id`), and P&T adds a DNS
      record for it pointing at the pool's App Gateway IP (`10.120.2.10` in pool01)

## Known gaps for Tiers 2 and 3

Tiers 2 and 3 are proposed (ADR 0014) and tested offline only. What the repo doesn't do for them yet, and what
that means for the steps above:

- **Not in the pipeline.** `scripts/clients.sh`, `terraform-pr.yml` and `_apply-client.yml` only know
  `terraform/clients/*`. For cells and pools, CI runs the stamp tests and type-checks every config
  (`scripts/test-client-configs.sh`) but doesn't plan or apply, so the applies above run outside the ring
  rollout, and nothing starts `job-index-admin` automatically.
- **Deployment identities.** `terraform/platform` only creates the Tier 1 shape: Contributor and the
  conditioned RBAC Administrator role on a whole subscription. That suits a pool. A cell's identity needs the
  extra rights listed above, and a cell client's identity needs the same federated credential, state
  container and AcrPull delegation with no subscription role at all. Neither shape is in Terraform yet.
- **Routed clients in a cell.** The reference hub (`terraform/hub`) has one entry per spoke. Two routed
  clients in one cell share a VNet and address range, which its overlap check refuses, and it would ask for
  two peerings to the same VNet. P&T's hub needs one peering per cell plus a connection, route and firewall
  rule per routed client.
- **Per-tenant keys in a pool.** `tenants.<tenant>.cmk_key_id` points a tenant's encryption scope at its own
  key, but the pool's storage account has no managed identity to read that key yet (part of the
  customer-managed key gap in the [README](../../README.md#status-and-known-gaps)).
