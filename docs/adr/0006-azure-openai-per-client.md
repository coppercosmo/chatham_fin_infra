# ADR 0006: Dedicated Azure OpenAI / AI Foundry per client, data-zone deployments

- Status: Accepted
- Date: 2026-11-13

## Decision
- Each client subscription has its **own Azure OpenAI account** (an AI Services / Foundry resource
  can be swapped in with the same pattern) with a custom subdomain, `public_network_access` off,
  `local_auth` off, network ACL default `Deny`, reached through a private endpoint.
- Model deployments are defined per client in config, defaulting to:
  - a chat model (e.g., `gpt-4o`) and an embeddings model (`text-embedding-3-large`)
  - **`DataZoneStandard` SKU**, so prompts and completions are processed inside the US (or EU)
    data zone. `GlobalStandard` is opt-in per client; regional `Standard` or provisioned
    throughput is used when a client contract requires single-region processing or guaranteed capacity.
- Optional **Azure AI Search** per client for RAG, private, keyless, `disableLocalAuth`.
- Content filtering stays at Microsoft defaults; any change goes through an ADR with the client.
- Abuse-monitoring opt-out (no human review of prompts) is applied for per Microsoft's
  modified-access process where a client requires it; this is tracked per client in config/notes.

## Why per client and not a shared AOAI account with per-client deployments
- Quota and rate limits are per account/subscription: a shared account means one client's batch
  job throttles another's chatbot.
- Logs and diagnostic data (which can include prompt metadata) stay in the client's workspace.
- RBAC on a shared account cannot be scoped to a single deployment cleanly.

## Consequences
- Each client needs quota approved in its subscription and region. Request quota as part of
  onboarding (runbook step), not at go-live.
- Model version upgrades are rolled out by ring (ADR 0008), not all clients at once.
