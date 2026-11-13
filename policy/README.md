# Proposed AI guardrails (for Platform Engineering to own)

These are **proposals to P&T**, not policies we assign ourselves (ADR 0002). Each one codifies a
rule our stamp already follows, so assigning it at the `AI Advisory` management group costs us
nothing and protects against anyone deploying AI services outside the stamp.

| File | Effect | Why |
|---|---|---|
| `deny-cognitive-services-local-auth.json` | Deny AI services with API keys enabled | Keys get pasted into notebooks and tickets; managed identity can't be |
| `deny-cognitive-services-public-network.json` | Deny AI services with public network access | Client prompts must stay on private networking |
| `allowed-openai-deployment-skus.json` | Deny model deployments outside approved SKUs (e.g. GlobalStandard) | Data residency: prompts processed only in the approved data zone |

Many of these exist as built-ins (search the portal for "Azure AI Services resources should have key
access disabled" and "... should restrict network access"); prefer the built-in where it exists
and use these custom definitions only for gaps such as deployment SKU.
