# Interview topic map

Where each topic the technical team will probe lives in this repo, and the 30-second answer.

| Topic (from recruiter notes) | Where in the repo | 30-second answer |
|---|---|---|
| **Designing Azure environments** | [ADR 0001](../adr/0001-tenancy-subscription-per-client.md), [overview](../architecture/overview.md) | Subscription per client inside P&T's management group. Same stamp for every client; only a ~30-line config changes. Shared platform sub holds nothing with client data. |
| **Networking / private endpoints** | [ADR 0003](../adr/0003-private-networking.md), `modules/spoke-network`, `modules/private-endpoint` | Hub-and-spoke. Every PaaS has public access off and a private endpoint. Spokes never peer with each other. Egress forced through the hub firewall. In the landing zone, P&T's DINE policy owns `privatelink` DNS records, so the module deliberately doesn't manage the DNS zone group. |
| **Identity and access** | [ADR 0004](../adr/0004-identity-managed-identity-no-secrets.md), `modules/workload-identity`, `modules/deployment-identity` | No keys anywhere: local auth off on AOAI, Search, Storage, App Insights. App uses a user-assigned MI with resource-scoped data roles. Humans: P&T groups, Reader standing, write via PIM. Pipelines: OIDC, one identity per client, RBAC Admin constrained by an ABAC condition so it can't grant Owner. |
| **Terraform reusable modules / repeatable envs** | [ADR 0007](../adr/0007-terraform-layout-and-state.md), `terraform/` | Modules -> one stamp root module -> per-client tfvars. State per client in its own container. No workspaces, no giant `for_each` over clients. Offline tests (`terraform test` with a mocked provider) assert the security properties. |
| **Per-client isolation / security** | ADR 0001, 0003, 0004, 0006, 0009 | Isolation at every layer: subscription, network, identity, AOAI account and quota, logs, state, pipeline identity, GitHub Environment. Explain it as "locked rooms with the same floor plan". |
| **Azure OpenAI / AI Foundry** | [ADR 0006](../adr/0006-azure-openai-per-client.md), `modules/ai-services` | Dedicated account per client (quota and logs isolation), `DataZoneStandard` by default for residency, no auto model upgrades so new versions roll out by ring. |
| **Compute choice** | [ADR 0005](../adr/0005-compute-container-apps.md) | Container Apps internal env: no clusters for a small team to babysit across N subscriptions. AKS per client only when a client needs GPUs or deep control. |
| **CI/CD across client environments** | [ADR 0008](../adr/0008-cicd-ring-based-fan-out.md), `.github/workflows/` | PR: fmt/validate/test/tflint/checkov + plan only for affected clients. Main: ring 0 (internal) -> ring 1 (pilots) -> ring 2 (all), approvals per environment. Nightly drift detection opens issues. |
| **Monitoring** | [ADR 0009](../adr/0009-observability-per-client.md), `modules/observability` | Per-client Log Analytics (logs can contain prompts = client data). Central workbook reads across workspaces. AOAI 429s and token usage vs. quota are first-class alerts. |
| **Working inside P&T guardrails** | [ADR 0002](../adr/0002-work-inside-platform-engineering-guardrails.md), `policy/` | Landing-zone consumer, not a shadow platform. Ask for a vending contract with an SLA, prove compliance in CI, propose AI-specific policies for P&T to own. |
| **AI coding tools** | [ai-coding-tools.md](ai-coding-tools.md) | How this repo was built with an AI assistant and how the output was reviewed. |

## Honest trade-offs to volunteer (shows judgment)
- Per-client fixed cost (PEs, LAW, CAE) is real, roughly a few hundred USD/month idle. Priced into hosted engagements.
- Vending speed depends on P&T. Mitigation: a pre-agreed template and a small pool of pre-vended subscriptions.
- GitHub-hosted runners can't reach private data planes, so the state account keeps a restricted public endpoint until self-hosted runners exist. Called out as a known gap with a plan.
- Shared PTU capacity across clients is impossible with this model. If cost demands it, that's a new ADR, not a quiet exception.
