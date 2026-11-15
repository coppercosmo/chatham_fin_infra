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
