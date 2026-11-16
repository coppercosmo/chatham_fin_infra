# Observability per client

How logs, metrics and cost data stay separated by client, how the team still sees everything, and how
alerts can gate a rollout. Related: [ADR 0009](../../adr/0009-observability-per-client.md),
[ADR 0012](../../adr/0012-ai-gateway-api-management.md) (token metrics),
[ADR 0008](../../adr/0008-cicd-ring-based-fan-out.md) (rings).

## Why logs are client data

Diagnostic logs from an AI app can contain prompt fragments, document names, user names and error
messages that quote input. So logs get the same boundary as the data: **a Log Analytics workspace per
client** (Tiers 1 and 2), with the client's own retention.

## Two ways to separate logs

| | Workspace per client (chosen for Tiers 1 and 2) | Shared workspace, resource-context access |
|---|---|---|
| How | Every client's resources send diagnostics to that client's workspace | Everything goes to one workspace; people query "by resource" and see only rows from resources they have access to |
| Isolation | Strong: a separate resource, its own RBAC, retention, region and (with a dedicated cluster) key | Medium: depends on RBAC on each resource and the workspace's access mode; one workspace-level role sees everything |
| Retention per client | Yes | Per table, not per client |
| Cost | Small per-workspace overhead; pay per GB either way | Slightly cheaper to run |
| Cross-client view | Cross-workspace queries (up to 100 workspaces per query) or a workbook | Easy: one workspace |
| Used here | Tier 1, Tier 2 client resources | Tier 2 cell's shared infrastructure; Tier 3 pool |

**At scale:** an Azure Monitor **dedicated cluster** (commitment from 100 GB/day) can link up to 1,000
workspaces. It makes cross-workspace queries faster and lets you use a customer-managed key for logs,
but the key is per cluster, not per workspace. Worth it once the total volume passes the commitment
tier, not before.

## What lands where in each tier

- **Tier 1:** everything in the client's workspace.
- **Tier 2:** client resources (vault, storage, model account, search diagnostics for the client's
  index, the app's App Insights) go to the client's workspace. The cell's App Gateway, WAF, APIM and
  Container Apps environment logs go to the **cell's** workspace, which the platform team reads. APIM
  logs **no request or response bodies** (`body_bytes = 0`). One caveat to say out loud: container
  console output goes to the environment's destination, which is the cell's workspace, so apps must
  send their own telemetry to the client's App Insights (connection string per client) and never print
  prompts to stdout.
- **Tier 3:** one pool workspace. Every row carries the tenant (the gateway's `Tenant` dimension and
  the app's tenant property), so per-tenant views are queries, not separate stores.

## Token and cost showback through the AI gateway

Token use is the variable cost of an AI app. The AI gateway (APIM) emits a metric on every model call
(`llm-emit-token-metric`), with dimensions `Client` (or `Tenant` in the pool) and `CallerAppId`. That
gives cost per client even where the model account is shared:

```kusto
// Tokens per client per day (App Insights customMetrics, namespace "ai-gateway")
customMetrics
| where timestamp > ago(30d) and name == "Total Tokens"
| extend client = tostring(customDimensions["Client"]), tenant = tostring(customDimensions["Tenant"])
| summarize tokens = sum(valueSum) by bin(timestamp, 1d), who = iff(isempty(tenant), client, tenant)
| extend approx_usd = tokens / 1000000.0 * 2.50   // illustrative blended price per 1M tokens
```

One catch to know: APIM only forwards these metrics to App Insights when the API diagnostic's custom
metrics switch is on, and azurerm 4.81 doesn't expose it yet (README known gaps), so today that is one
`azapi` setting or a portal toggle per API.

Fixed costs come from tags: `client`, `cell` or `pool`, and `isolation_tier` on every resource group
(required by policy), so Cost Management can group by client. Shared cell or pool costs are split by
the token share above, or evenly per client, whichever the finance team prefers.

## Alerts that gate ring promotion

ADR 0008 rolls changes out in rings (internal, pilots, everyone). The question is how a ring "passes".
A simple, defensible rule: after applying ring N, wait a soak period, then check a small set of
signals for the clients in that ring before ring N+1 can start.

| Signal | Source | Fails the ring if |
|---|---|---|
| HTTP 5xx rate at the front door | App Gateway access logs | Above 1% for 10 minutes |
| Model throttling (HTTP 429) | APIM or Azure OpenAI metrics | Above the client's baseline |
| p95 latency to the model | App Insights dependencies | 30% above last week's same hour |
| Container restarts | Container Apps metrics | Any crash loop |
| Key Vault `Forbidden` | Vault diagnostics | Any new identity being refused (a role change went wrong) |

In the deploy workflow this is a job between rings that runs the queries (or reads fired alert state)
and fails if any breach is found, so the next ring's approval never appears.

Honest status in this repo: ADR 0009 says the stamp deploys metric alerts, but the observability module
only creates the workspace, App Insights and diagnostic settings today. Adding
`azurerm_monitor_metric_alert` resources for the signals above, and the gate job, is the next step.

## Interview questions and answers

**"Workspace per client or one big workspace?"**
Per client for anything that can contain client data, because it's a real boundary with its own
retention and access. Shared workspaces with resource-context access are fine for platform logs that
don't contain client content. If volume grows, a dedicated cluster can link up to 1,000 workspaces and
speed up cross-workspace queries.

**"How do operators see across 200 clients then?"**
A workbook and saved queries that use cross-workspace queries (up to 100 workspaces per query, so group
them), run by a read-only operations group. Alerts are per client and route to one action group.

**"How do you charge clients for model usage when the gateway is shared?"**
The gateway emits a token metric per call with the client or tenant as a dimension. That gives tokens
per client per day; multiply by price. Fixed costs come from tags.

**"How do you know a rollout is safe to continue?"**
Soak, then check error rate, throttling, latency, restarts and access-denied counts for the ring that
just changed. If any breach, the pipeline stops before the next ring.
