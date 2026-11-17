# Kubernetes manifests (AKS option, ADR 0011)

Applied to a client's cluster after the stamp creates it. Values in `<angle brackets>` come from
the stamp's Terraform outputs (`terraform output`). In production these are rendered per client and
reconciled by **Flux (AKS GitOps extension)** from this repo, so the cluster pulls its config and
CI never needs credentials to the private API server.

| File | What it does |
|---|---|
| `ingress-controller.yaml` | Managed NGINX (app routing add-on) on an **internal** load balancer with a static IP. App Gateway targets that IP. No public IP is ever created in the cluster. |
| `app.yaml` | Namespace (restricted Pod Security), workload-identity service account, ConfigMap of endpoints, hardened Deployment, Service, Ingress with the TLS cert from Key Vault. |
| `network-policy.yaml` | Default deny in the app namespace; allow only NGINX in, and only DNS + the VNet (private endpoints, via the hub) out. |
| `ingest-cronjob.yaml` | Document ingestion (ADR 0015) as a CronJob: its own workload-identity service account (the client's ingestion identity, not the app's), the same settings as the Container Apps job in `modules/ingestion-job`, off-peak schedule, hardened pod. The network policy lets nothing in. |

Request path: client -> App Gateway WAF (TLS) -> internal NGINX at `aks_ingress_internal_ip` (TLS, same
cert from Key Vault) -> `advisor-api` pod -> Azure OpenAI / Search / Storage through private endpoints,
authenticating as the client's managed identity via workload identity.
