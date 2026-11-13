# Architecture overview

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

## 3. Request path

```mermaid
sequenceDiagram
  participant U as Client user (SSO)
  participant GW as P&T ingress (App GW / Front Door + Private Link)
  participant API as ca-api (client sub)
  participant ID as Entra ID
  participant AOAI as Azure OpenAI (private endpoint)
  participant SRCH as AI Search (private endpoint)
  U->>GW: HTTPS (Entra ID auth, client tenant via B2B or app registration)
  GW->>API: private, internal Container Apps env
  API->>ID: get token as id-acme-app (no secrets)
  API->>SRCH: retrieve client documents
  API->>AOAI: chat completion (DataZoneStandard)
  AOAI-->>API: response
  API-->>U: answer
```

## 4. What makes it multi-client without being shared
| Layer | Shared across clients? | Why |
|---|---|---|
| Terraform modules and stamp | Yes (code) | Build once |
| Container images | Yes (same digest promoted by ring) | Build once |
| ACR, TF state storage, CI runners | Yes, platform sub, **no client data** | Cost, simplicity |
| Subscription, VNet, AOAI, KV, Storage, Search, logs | **No** | Isolation (ADR 0001) |
| Deployment identity, GitHub Environment | **No** | Pipeline blast radius (ADR 0008) |
