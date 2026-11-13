# ADR 0009: Per-client Log Analytics, central read-only view

- Status: Accepted
- Date: 2026-11-13

## Decision
- Each client subscription has its own Log Analytics workspace and workspace-based Application
  Insights (local auth disabled). Diagnostic settings from Key Vault, Azure OpenAI, AI Search,
  Storage and Container Apps go there. Logs may contain prompt fragments, so they are client data.
- Retention per client config (default 90 days; longer if the client's records policy requires).
- **Cross-client operations view**: an Azure Monitor workbook in the platform subscription
  queries all client workspaces (`workspace("...")`), using a read-only operations group. Alerts
  (availability, 5xx rate, AOAI 429 throttling, token usage vs. quota, Key Vault access denied)
  are deployed by the stamp and route to a shared action group.
- P&T's security tooling (Defender for Cloud / Sentinel) gets what it needs through their own
  policies; we don't duplicate it.
- A per-client **budget** with alerts at 80% and 100% is part of the stamp, owned by the
  engagement lead.

## Key signals for AI workloads
| Signal | Source | Why |
|---|---|---|
| AOAI `429` rate and `ProcessedPromptTokens` | AOAI metrics | Quota planning per client |
| p95 latency per model deployment | AOAI metrics / App Insights dependency | Client SLA |
| Container App restarts, replica count | Container Apps metrics | Health |
| Key Vault `Forbidden` responses | KV diagnostics | Misconfigured or malicious access |
