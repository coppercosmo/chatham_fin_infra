# Architecture Decision Records

Short, dated records of decisions and the trade-offs behind them. Format: context, decision,
consequences, alternatives. A decision can be superseded by a later ADR; it is never edited away.

| #    | Decision | Status |
|------|----------|--------|
| [0001](0001-tenancy-subscription-per-client.md) | One Azure subscription per client | Accepted |
| [0002](0002-work-inside-platform-engineering-guardrails.md) | Build inside the central Platform Engineering landing zone | Accepted |
| [0003](0003-private-networking.md) | Private endpoints only, hub-and-spoke | Accepted |
| [0004](0004-identity-managed-identity-no-secrets.md) | Managed identity everywhere, no keys | Accepted |
| [0005](0005-compute-container-apps.md) | Azure Container Apps (internal) as default compute | Accepted |
| [0006](0006-azure-openai-per-client.md) | Dedicated Azure OpenAI / AI Foundry per client, data-zone deployments | Accepted |
| [0007](0007-terraform-layout-and-state.md) | Module + stamp + per-client config, state per client | Accepted |
| [0008](0008-cicd-ring-based-fan-out.md) | Ring-based CI/CD fan-out with OIDC and per-client identities | Accepted |
| [0009](0009-observability-per-client.md) | Per-client Log Analytics, central read-only view | Accepted |
| [0010](0010-private-ingress-app-gateway-waf.md) | Private ingress through a per-client Application Gateway WAF_v2 | Accepted |
| [0011](0011-aks-hosting-option.md) | AKS as a per-client hosting option (dedicated private cluster) | Accepted, amends 0005 |
| [0012](0012-ai-gateway-api-management.md) | AI gateway (API Management) between client apps and models | Accepted, piloting |
| [0013](0013-client-network-connectivity.md) | Client network connectivity: Private Link first, then ExpressRoute or VPN through the hub | Accepted, amends 0010 |
