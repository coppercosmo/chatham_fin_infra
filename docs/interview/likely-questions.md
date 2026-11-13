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
