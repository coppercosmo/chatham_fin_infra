# Architecture overview

The full multi-client diagram, with every component for three example clients, is
[diagram/solution-architecture.svg](diagram/solution-architecture.svg) (PNG:
[solution-architecture.png](diagram/solution-architecture.png)). The sections below break it down
piece by piece.

To change it, edit [diagram/generate.py](diagram/generate.py) and regenerate:

```bash
python3 docs/architecture/diagram/generate.py
NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs   # PNG, needs Playwright
```

## 1. Where this sits in Chatham's Azure estate

```mermaid
flowchart TB
  ROOT[Tenant root MG] --> CH[Chatham MG<br/>P&T policies]
  CH --> PLAT[Platform MG<br/>P&T: connectivity, identity, management]
  CH --> LZ[Landing zones MG]
  LZ --> CORP[Corp MG]
  CORP --> AIA[AI Advisory MG<br/>P&T assigns AI guardrails]
  AIA --> AIP[sub: AI Advisory Platform<br/>ACR, TF state, deploy identities, runners]
  AIA --> CL[AI Advisory / Clients MG]
  CL --> S1[sub: client acme-insurance]
  CL --> S2[sub: client chatham-internal]
  CL --> S3[sub: client ...]
```

P&T owns every management group, policy assignment, and the connectivity subscription. AI Advisory
owns what's inside the platform subscription and the client subscriptions.

## 2. One client stamp

```mermaid
flowchart TB
  subgraph SUB["Client subscription (one per client)"]
    subgraph RG["rg-acme-prd-eus2"]
      subgraph VNET["vnet-acme-prd-eus2 (10.100.0.0/22)"]
        subgraph APPS["snet-apps /24 (delegated Microsoft.App)"]
          CAE[Container Apps env<br/>internal]
          API[ca-api]
          JOB[Ingestion job]
        end
        subgraph PE["snet-pe /26"]
          PE1((pe-oai))
          PE2((pe-kv))
          PE3((pe-blob))
          PE4((pe-srch))
        end
      end
      AOAI[Azure OpenAI<br/>public off, keys off]
      KV[Key Vault<br/>RBAC, purge protection]
      ST[Storage<br/>shared key off]
      SRCH[AI Search<br/>optional]
      MI[id-acme-app]
      LAW[Log Analytics + App Insights]
      BUD[Budget]
    end
  end
  API -- managed identity --> PE1 --> AOAI
  API --> PE2 --> KV
  API --> PE3 --> ST
  API --> PE4 --> SRCH
  CAE -. logs .-> LAW
  AOAI -. diagnostics .-> LAW
  VNET <-- peering --> HUB[P&T hub: firewall, DNS, ingress]
```

## 3. Request path (Container Apps)

```mermaid
sequenceDiagram
  participant U as Client user (SSO)
  participant GW as App Gateway WAF_v2 (client spoke, private IP)
  participant API as ca-api (client sub)
  participant ID as Entra ID
  participant AOAI as Azure OpenAI (private endpoint)
  participant SRCH as AI Search (private endpoint)
  U->>GW: HTTPS to acme.ai.<domain> (via hub: ExpressRoute/VPN, or Front Door Private Link)
  Note over GW: TLS terminated with cert from client Key Vault.<br/>WAF: DRS 2.1 + Bot Manager, rate limit
  GW->>API: HTTPS re-encrypted to env static IP, host header = app FQDN
  API->>ID: get token as id-acme-app (no secrets)
  API->>SRCH: retrieve client documents
  API->>AOAI: chat completion (DataZoneStandard)
  AOAI-->>API: response
  API-->>U: answer
```

## 4. Ingress (ADR 0010)

```mermaid
flowchart LR
  subgraph Users
    PRIV[Client network<br/>ExpressRoute / VPN]
    INET[Internet users<br/>public mode only]
  end
  subgraph Hub["P&T hub"]
    DNS[DNS: acme.ai.domain -> 10.100.6.10]
    FD[Front Door Premium<br/>optional global edge]
  end
  subgraph Spoke["Client spoke"]
    subgraph AGWS["snet-agw /24"]
      AGW[App Gateway WAF_v2<br/>private frontend 10.100.6.10]
    end
    WAF{{WAF policy<br/>Prevention, DRS 2.1, Bot 1.1<br/>prompt-field exclusions<br/>rate limit / IP allow-list}}
    KV[(Key Vault<br/>listener cert)]
    BE[Container Apps env IP<br/>or AKS internal NGINX IP]
  end
  PRIV --> DNS --> AGW
  INET -. NSG + WAF allow-list .-> AGW
  FD -. Private Link .-> AGW
  AGW --- WAF
  AGW -. UAMI: Key Vault Secrets User .-> KV
  AGW -- HTTPS, SNI, 180s timeout, streaming --> BE
```

## 5. AKS variant of the stamp (ADR 0011)

```mermaid
flowchart TB
  subgraph SUB["Client subscription"]
    AGW[App Gateway WAF_v2]
    subgraph AKS["Private AKS cluster (Entra only, Azure RBAC)"]
      NGINX[Managed NGINX<br/>internal LB, static IP]
      subgraph NS["namespace advisor (restricted PSS, default-deny netpol)"]
        POD[advisor-api pods<br/>service account: advisor-api]
      end
      GPU[gpu pool<br/>tainted, scale from 0]
    end
    MI[id-client-app<br/>federated to advisor:advisor-api]
    AOAI[Azure OpenAI]
    KV[Key Vault]
  end
  AGW --> NGINX --> POD
  POD -- workload identity token --> MI
  MI --> AOAI
  MI --> KV
  POD -. optional self-hosted model .-> GPU
```

Nodes use Azure CNI Overlay with Cilium. Egress goes through the hub firewall (UDR). P&T's Azure
Policy runs inside the cluster through the Azure Policy add-on, and Flux deploys `kubernetes/`.

## 6. AI gateway (ADR 0012)

```mermaid
sequenceDiagram
  participant API as App (client sub)
  participant GW as APIM AI gateway (internal, snet-apim)
  participant CS as Content Safety (optional)
  participant P as AOAI primary (PTU)
  participant S as AOAI secondary (PAYG / 2nd region)
  API->>GW: chat completion + Entra token (app identity)
  GW->>GW: validate token, token limit per caller
  GW->>CS: Prompt Shields
  GW->>P: forward as gateway managed identity
  P-->>GW: 429 (saturated)
  GW->>S: failover (circuit breaker trips primary)
  S-->>GW: completion
  GW->>GW: emit token metric (Client, CallerAppId)
  GW-->>API: completion + remaining-token headers
```

With the gateway on, the app has no role on the model accounts, so every call goes through it.

## 7. What makes it multi-client without being shared
| Layer | Shared across clients? | Why |
|---|---|---|
| Terraform modules and stamp | Yes (code) | Build once |
| Container images | Yes (same digest promoted by ring) | Build once |
| ACR, TF state storage, CI runners | Yes, platform sub, **no client data** | Cost, simplicity |
| Subscription, VNet, AOAI, KV, Storage, Search, logs | **No** | Isolation (ADR 0001) |
| App Gateway, WAF policy, TLS certificate | **No** | Per-client edge, logs and blast radius (ADR 0010) |
| AKS cluster (when used) | **No** | Dedicated cluster per client (ADR 0011) |
| AI gateway (APIM) | **No** by default | Per client in the stamp; a shared APIM only for internal apps or with per-client workspace gateways (ADR 0012) |
| Deployment identity, GitHub Environment | **No** | Pipeline blast radius (ADR 0008) |
