# Mock technical test

A practice set shaped like the technical round: Terraform fundamentals, a from-scratch exercise,
Azure networking and identity, isolation design scenarios and a debugging round. Cover the model
answer, answer out loud (or on paper), then compare. Times are a guide for a 90-minute session.

Model answers are deliberately short: the length you'd say in an interview, then stop and let them ask.

---

## Part A: Terraform fundamentals (20 minutes)

**A1. `count` or `for_each`: when do you use which?**
> `for_each` over a map or set whenever the things have identities, like clients, subnets or private
> endpoints. Each instance is addressed by its key (`azurerm_subnet.this["pe"]`), so removing one
> doesn't shift the others. `count` addresses by index, so deleting item 0 renumbers everything after
> it and Terraform wants to destroy and recreate them. I use `count` only for "zero or one" toggles,
> like `count = var.enable_search ? 1 : 0`.

**A2. You get "Invalid for_each argument ... depends on resource attributes that cannot be determined
until apply". What does it mean and how do you fix it?**
> The **keys** of a `for_each` must be known at plan time. Usually someone wrote
> `for_each = toset([azurerm_x.a.id, ...])`. Fix: key by something static (a name from config) and put
> the unknown ID in the value: `for_each = { blob = { id = azurerm_storage_account.this.id } }`. Values
> can be unknown; keys can't. The exercise in Part B does exactly this.

**A3. How do you version modules, and how are they consumed?**
> Modules live in a registry or a Git repo with semantic version tags. A breaking change to inputs or
> to resource addresses is a major version. Roots pin a version (`version = "~> 2.3"` from a registry,
> or `?ref=v2.3.1` for Git) and upgrade deliberately with a plan to review. Inside a module I constrain
> providers loosely (`>= 4.81, < 5.0`); the root pins exactly and the `.terraform.lock.hcl` file pins
> provider builds. In this repo the modules are in the same repo as the stamps, so the version is the
> commit, and ring-based rollout (ADR 0008) is how a module change reaches clients gradually.

**A4. How would you lay out state for 200 clients?**
> One state per client environment (and one per cell or pool), never one state for everything. The
> state is the blast radius of a bad apply and the lock is a bottleneck. Remote backend in an Azure
> storage account with Entra ID auth (`use_azuread_auth = true`), blob lease locking, versioning and
> soft delete on, private endpoint, and access limited to the deployment identities. Separate
> containers per client so each client's identity can only read its own state. State can contain
> secrets, so treat the account like a Key Vault.

**A5. You renamed `azurerm_storage_account.data` to `azurerm_storage_account.this`. The plan wants to
destroy and recreate it. What do you do?**
> Add a `moved` block: `moved { from = azurerm_storage_account.data  to = azurerm_storage_account.this }`.
> The plan then shows a move, no destroy. Same for moving a resource into a module
> (`to = module.storage.azurerm_storage_account.this`) or from `count` to `for_each`
> (`from = x.y[0]  to = x.y["blob"]`). Keep the block for a release or two so every state has moved,
> then delete it. Before `moved` existed this was `terraform state mv`, which is manual and not reviewed.

**A6. Someone created a resource in the portal. How do you bring it under Terraform?**
> An `import` block (`import { to = azurerm_resource_group.x  id = "/subscriptions/.../resourceGroups/rg-x" }`)
> plus the resource configuration; `terraform plan -generate-config-out=generated.tf` can draft the
> config. Plan until it shows no changes, then apply. It goes through a pull request like everything
> else, unlike the old `terraform import` command.

**A7. Name the `lifecycle` arguments and one real use of each.**
> `prevent_destroy` (a Key Vault or storage account with client data), `ignore_changes` (tags that a
> policy's Modify effect adds, so Terraform doesn't fight Azure Policy), `create_before_destroy`
> (certificates, or anything referenced by name that must not have a gap), `replace_triggered_by`
> (replace a container app job when its config changes), and `precondition`/`postcondition` (fail
> the plan with a clear message, for example "Private Link needs a dedicated subnet").

**A8. How do you test Terraform without an Azure subscription?**
> `terraform validate`, `tflint` and Checkov for static checks, and `terraform test` with
> `mock_provider "azurerm"` for behaviour: run a plan with given variables and assert on the planned
> resources, for example "every client's private endpoint is in its own subnet" or "a confidential
> tenant is refused". Every stamp and module here has those tests and CI runs them on every pull
> request. Real plans against Azure run per client after that.

**A9. Workspaces or directories for environments?**
> Directories (or separate var files and backends) for anything with different access or risk, like
> dev and prod or two clients, because CLI workspaces share one backend and one set of credentials and
> it's too easy to apply to the wrong one. Workspaces are fine for short-lived copies of the same thing.

**A10. What's in your PR pipeline for Terraform?**
> fmt check, validate, tflint, Checkov, offline tests, then a plan for every affected environment
> posted on the PR. Apply on merge, ring by ring, with each job only able to get a token for its own
> client (OIDC federated credential per GitHub environment). Nightly drift detection with
> `plan -detailed-exitcode`.

---

## Part B: from-scratch exercise (25 minutes)

> **Task.** Without using any modules, write Terraform that creates: a resource group; a VNet
> (default `10.50.0.0/22`) with a workload subnet and a private-endpoint subnet; an NSG on each subnet,
> with the endpoint subnet allowing 443 only from the workload subnet; a storage account and a Key Vault,
> both with public network access disabled and no shared keys or access policies; a private endpoint for
> each, registered in the right private DNS zones, linked to the VNet. Use `for_each` for the endpoints.
> Validate the inputs.

Try it first. Then compare with the model solution in
[`terraform/exercises/vnet-private-endpoint`](../../../terraform/exercises/vnet-private-endpoint)
(runs offline: `terraform init -backend=false && terraform test`).

What an interviewer looks for, and the common mistakes:

| Look for | Common mistake |
|---|---|
| `private_dns_zone` **and** `private_dns_zone_virtual_network_link` per zone | Zone without a link: the endpoint works but the name still resolves to the public IP |
| Right zone names: `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net` (Azure OpenAI: `privatelink.openai.azure.com`, Search: `privatelink.search.windows.net`) | `privatelink.vault.azure.net` (wrong), or one zone for everything |
| Right sub-resource (`subresource_names`): `blob`, `vault` (OpenAI: `account`, Search: `searchService`) | `storage` or `keyvault` |
| `private_dns_zone_group` on the endpoint, so the A record is written for you | Hand-written `azurerm_private_dns_a_record` with a hard-coded IP |
| `private_endpoint_network_policies = "Enabled"` on the endpoint subnet | NSG on the subnet that silently doesn't apply to endpoints |
| `for_each` keyed by static names, IDs in the values | `for_each = toset([azurerm_storage_account.this.id])`: unknown keys at plan |
| `public_network_access_enabled = false`, `shared_access_key_enabled = false`, Key Vault `rbac_authorization_enabled = true` | Public access left on "for now" |
| `cidrsubnet()` to carve subnets, validation on the CIDR | Hard-coded subnet ranges that break when the VNet range changes |
| `registration_enabled = false` on the link | Turning on auto-registration (that's for VM records, not endpoints) |

Talking points while you write: in a landing zone the DNS zones live in P&T's hub and a
DeployIfNotExists policy creates the zone group, so a stamp doesn't write DNS itself (see the
landing-zones deep dive). And the provider needs `storage_use_azuread = true` once shared keys are off.

---

## Part C: Azure networking and DNS (15 minutes)

**C1. Explain how a private endpoint name resolves, from an app in a spoke and from a client's office.**
> The public name `st1.blob.core.windows.net` is a CNAME to `st1.privatelink.blob.core.windows.net`.
> Inside Azure, the VNet's DNS (or the hub's DNS Private Resolver) finds the `privatelink` zone linked
> to it and returns the endpoint's private IP. Outside the zone's reach you'd get the public IP, which
> is blocked. From the office, the on-premises DNS server conditionally forwards `blob.core.windows.net`
> (and the other privatelink parents) to the Private Resolver's inbound endpoint in the hub, so the
> office gets the private IP too, over ExpressRoute or VPN.

**C2. Service endpoint or private endpoint?**
> A service endpoint keeps the PaaS service's public IP but lets the firewall on the service trust a
> subnet. A private endpoint gives the service a private IP inside your VNet, so it works from
> on-premises and peered networks, can be locked to that one resource (no data exfiltration to other
> storage accounts) and lets public access be turned off completely. For client data, private endpoints.

**C3. What does 168.63.129.16 do?**
> It's Azure's virtual public IP for platform services: Azure DNS, health probes, DHCP. If a VNet uses
> Azure-provided DNS, queries go there. NSGs and UDRs that block it break DNS and load balancer probes.

**C4. Hub and spoke: how does a spoke reach the internet, and how do two spokes talk?**
> A route table on the spoke subnets sends `0.0.0.0/0` to the hub firewall's private IP, so egress is
> filtered and logged centrally. Peering isn't transitive, so spoke to spoke also goes through the
> firewall, and here it's denied by default because spokes are different clients.

**C5. Two clients use the same `10.0.0.0/16`. Can both connect through the same hub?**
> Not as-is, because the hub can't route one range to two places. Options: Private Link (the client
> creates an endpoint in their own VNet, no routing at all, best when they're on Azure), NAT on the VPN
> gateway, or the client advertising a unique range. ADR 0013 covers this.

**C6. NSG or Azure Firewall?**
> Both. NSGs are layer-4 allow/deny at the subnet or NIC, cheap and close to the workload. The
> firewall is central, stateful, does FQDN filtering and threat intelligence, and logs everything.
> Egress to the internet goes through the firewall with an FQDN allow-list; NSGs keep subnets apart.

---

## Part D: identity (10 minutes)

**D1. System-assigned or user-assigned managed identity?**
> System-assigned lives and dies with the resource, which is fine for one resource. User-assigned is a
> separate resource, so it can be created first, granted roles before the app exists (no race on first
> start), shared by a set of resources, and survive a replace. The stamps use user-assigned identities
> for apps and gateways for that reason.

**D2. How does GitHub Actions deploy to Azure without a secret?**
> Workload identity federation. The deployment identity has a federated credential that trusts tokens
> from GitHub's OIDC issuer with a specific subject, here
> `repo:<org>/<repo>:environment:client-<name>`. The job asks GitHub for a token and exchanges it with
> Entra ID for an Azure token. No secret is stored, and a job in another environment can't get that
> client's token.

**D3. Control plane versus data plane roles?**
> Control plane is managing the resource (create a storage account, change its firewall): roles like
> Contributor. Data plane is using what's inside (read a blob, get a secret, call a model): roles like
> Storage Blob Data Reader, Key Vault Secrets User, Cognitive Services OpenAI User. Contributor on a
> storage account doesn't let you read blobs when shared keys are off, which is why keys off plus data
> roles is a real boundary.

**D4. How do you let a pipeline create role assignments without letting it make anyone Owner?**
> Role Based Access Control Administrator with a condition that limits which role definitions it can
> assign (and optionally to which principal types), at the narrowest scope. The Tier 2 cell does this
> for each client's pipeline: it can assign only the seven roles its stamp needs, only in its own
> resource group.

**D5. Key Vault access policies or RBAC?**
> RBAC. One permission model across Azure, assignable at vault or secret scope, auditable in the
> activity log, and PIM-able. Access policies are vault-wide and live in the vault's own config.

---

## Part E: isolation design scenarios (15 minutes)

**E1. "We have 50 small clients to onboard next month, mostly trials using our own market research.
Budget is tight."**
> Tier 3, the pooled tier: one app, one host name, a tenant per client as a map entry and an Entra
> group, about 45 dollars a month each. Their data is internal or public, and the app reads it with the
> user's own token so Azure enforces the separation. I'd explain the trade-off (shared process and
> quota) to the engagement leads, and promote any trial that turns into confidential work to a cell.

**E2. "A client's vendor-risk team asks: is anything of ours shared with other clients?"**
> Depends on the tier, and we answer honestly. Tier 1: nothing except P&T's hub. Tier 2: the front
> door, compute environment and API gateway are shared; their documents, index, model account, keys,
> logs and identities are dedicated, and keys are disabled so only their identities can reach them.
> Tier 3: processed alongside others, with storage and search access checked by Azure per user. If the
> answer isn't acceptable to them, that decides their tier.

**E3. "Client wants a fine-tuned model on their data."**
> Tier 1. The fine-tuned model and its training files must live in their own account, and they will
> likely want PTU or dedicated capacity too. The cell and pool stamps refuse provisioned SKUs.

**E4. "One client's batch job is throttling everyone's chat."**
> In Tiers 1 and 2 that can't happen across clients: each has its own deployments and capacity. Within
> a client, separate deployments for batch and chat, a per-caller token limit at the gateway, and
> schedule batch off-peak. In Tier 3 the per-tenant gateway limit is the control; tune it.

**E5. "Platform Engineering says no to any new custom roles."**
> Then the Tier 2 per-client pipeline can't create locks or join the shared subnet with a narrow role.
> Options: P&T grants built-in Network Contributor on just the endpoint subnet (weaker, document it), or
> the cell pipeline creates the client's private endpoints itself. I'd ask which they prefer and record
> it in ADR 0014's open questions.

---

## Part F: debugging round (10 minutes)

**F1. The app gets HTTP 403 from storage, through the private endpoint.**
> Read the error code, because it tells you network or identity. `AuthorizationPermissionMismatch`
> ("...not authorized to perform this operation using this permission") is RBAC: does the app's identity
> have a **data** role (Storage Blob Data Reader/Contributor) on the account or container, and is the
> app actually using that identity (a user-assigned identity needs its client ID, e.g. `AZURE_CLIENT_ID`)?
> New role assignments can take a few minutes to apply. `AuthorizationFailure` ("...not authorized to
> perform this operation") usually means the storage firewall refused the source: check that the name
> resolves to the private IP from the app (`nslookup`), because a public-IP answer sends the request to
> the disabled public endpoint.

**F2. `nslookup kv-x.vault.azure.net` from the app returns a public IP.**
> The `privatelink.vaultcore.azure.net` zone isn't linked to the VNet the app uses (or to the hub
> resolver's VNet in a landing zone), or the endpoint has no zone group so there's no A record, or the
> VNet's custom DNS servers don't forward to Azure DNS or the resolver.

**F3. A plan shows every client's container app being replaced after a module change.**
> Stop. Find which attribute forces replacement (the plan marks it). Often it's a renamed resource
> (needs a `moved` block), a changed key in a `for_each`, or an attribute that can't be updated in
> place. Ring 0 exists to catch this before it reaches clients.

**F4. Azure OpenAI returns 429 for one client.**
> Check whether it's their deployment's TPM limit or the gateway's per-client limit (the response
> headers and the gateway metrics say which). Short term: honour `Retry-After`, slow their batch job,
> raise capacity within quota. Longer term: more quota, a second region behind the gateway, or PTU.
> Runbook: `docs/runbooks/incident-aoai-throttling.md`.

**F5. `terraform apply` fails creating a private endpoint with "LinkedAuthorizationFailed".**
> The identity running Terraform can create the endpoint in its resource group but lacks
> `Microsoft.Network/virtualNetworks/subnets/join/action` on the subnet, which is in another resource
> group (exactly the Tier 2 cell situation, solved by the join-only role).

---

## Part G: AI coding tools (5 minutes)

**G1. How do you use AI coding tools on infrastructure code safely?** See
[ai-coding-tools.md](../ai-coding-tools.md). The short version: the tool drafts, the pipeline checks
(fmt, validate, tflint, Checkov, tests, plan), a human reviews the plan, and the tool never has
credentials to apply.
