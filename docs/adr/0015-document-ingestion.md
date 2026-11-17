# ADR 0015: Document ingestion in every tier, and a content filter for RAG

- Status: Proposed, amends 0006 (content filtering) and, for Tier 2, 0014
- Date: 2026-11-17
- Plain-words version: [the AI layer, end to end](../interview/deep-dives/ai-architecture.md#ingest-steps-a-to-d-ahead-of-time)

## Context
RAG only works if each client's search index is already full of that client's chunks (split, embedded
and written ahead of time). Before this decision the repo did that unevenly:

- **Tier 1** gave AI Search's own identity the roles for an indexer, but not the **shared private links**
  an indexer needs when storage and the model account have public access off. As built, an indexer
  couldn't reach either.
- **Tier 2** let the client's **app identity** write its index. The app is the internet-facing part, so
  a bug or compromise in it could rewrite the index every answer is built from.
- **Tier 3** had per-tenant jobs, declared inline in the pool root.
- **Content filters** were Microsoft's default configuration, which leaves **indirect attack detection**
  (instructions hidden inside documents) off. For RAG it is the filter that matters most, because
  every retrieved chunk goes into the prompt.

A second question sits underneath: who creates the index itself (fields, vector settings, semantic
configuration)? Terraform's azurerm provider has no index resource, and the only Azure role that can
manage index definitions, **Search Service Contributor**, applies to the whole search service.

## Decision

### 1. One ingestion job, the same in every tier
`terraform/modules/ingestion-job` creates a scheduled Container Apps job per client (Tiers 1 and 2) or
tenant (Tier 3), `job-<code>-ingest`. Every job runs the same image (the app's repo, an ingestion entry
point, pinned by digest and promoted by ring) with the same settings contract:

| Setting | Meaning |
|---|---|
| `AZURE_CLIENT_ID` | The job's own identity, never the app's |
| `AZURE_STORAGE_BLOB_URL`, `AZURE_STORAGE_CONTAINER` | Where this client's documents are (`documents`, or the tenant's container in Tier 3) |
| `AZURE_SEARCH_ENDPOINT`, `AZURE_SEARCH_INDEX` | This client's index, named after the client |
| `AZURE_OPENAI_ENDPOINT`, `EMBEDDING_DEPLOYMENT` | The client's AI gateway URL, so embedding tokens are limited and metered like chat |
| `INGEST_MODE`, `MANAGE_INDEX` | `push` or `pull`; whether this job may change the index definition |
| `CHUNK_TOKENS`, `CHUNK_OVERLAP_TOKENS` | 512 and 128 to start; tuned with evaluations |

The job reads new or changed files, splits them, embeds each chunk through the gateway, writes chunk
text, vector and source to the index, and removes the chunks of deleted files. AKS clients run the same
contract as a CronJob (`kubernetes/ingest-cronjob.yaml`) with its own workload-identity service account.

### 2. Each job runs as its own client's ingestion identity

| | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| Identity | `id-<client>-ingest` in the client's subscription | `id-<client>-ingest` in the client's resource group (`cell-client`) | `id-<tenant>-ingest` in the pool |
| Documents | `Storage Blob Data Reader` on the `documents` container | Same | `Storage Blob Data Contributor` on the tenant's container (as ADR 0014) |
| Index | `Search Index Data Contributor` on its own index | Same, granted by the cell | Same |
| Index definition | `Search Service Contributor` on its **own** search service | No: the cell's index admin job | No: the pool's index admin job |
| Embeddings | Through the client's gateway, as a separate caller with its own token counter | Through the client's API on the shared gateway, sharing the client's token limit | Through the pool gateway, which maps the identity to its tenant |
| The app on the index | `Search Index Data Reader` | Drops from Contributor to `Search Index Data Reader` once the client has a job | No role (reads with the user's token) |

The module refuses two jobs sharing an identity, and two jobs writing one index.

### 3. Push by default; pull is a Tier 1 option
**Push** (the job does the work) is the default everywhere and the only option in shared tiers. **Pull**
(an AI Search indexer and skillset, `ingestion.mode = "pull"`) is allowed in Tier 1 only, because an
indexer runs as the search service's own identity, which on a shared service would need access to every
client's storage. When a Tier 1 client picks pull:

- Terraform creates two **shared private links** from the client's search service, to its storage
  (`blob`) and its model account (`openai_account`), and gives the search identity `Storage Blob Data
  Reader` and `Cognitive Services OpenAI User`. Those two roles no longer exist in push mode.
- Each link stays Pending until approved on the target. The client apply workflow approves it with
  `scripts/approve-shared-private-links.sh`, which approves only connections carrying the request
  message Terraform set for this client and reports anything else.
- The indexer must use the private execution environment, and its embedding calls skip the gateway.
  That trade-off is the client's to accept.

### 4. Index definitions in shared tiers belong to the platform
Each cell and pool gets a platform identity, `id-<cell|pool>-index-admin`, with Search Service
Contributor on the shared service, and a **manually started** job, `job-index-admin`, that creates or
updates the definition of every listed index. Search Service Contributor can manage (and delete) index
definitions but can't read or load documents. It is service-wide, so a client or tenant identity never
gets it. The job is started after onboarding and after a schema change. In Tier 1 the client's own job
does this (`MANAGE_INDEX = true`), because the search service is the client's alone.

### 5. A content filter for RAG on every model deployment
`modules/ai-services` creates a content filter configuration, `rag-default`, on every model account and
attaches it to every deployment:

- Microsoft's default, written down: hate, sexual, self-harm and violence checked on prompts and answers,
  blocking at medium severity and above; jailbreak detection; protected material (text and code).
- **Indirect attack detection on, and blocking.** It only checks text the app marks as documents, so the
  app wraps retrieved chunks in `""" <documents> ... </documents> """` with each chunk's text
  JSON-escaped.

Per client, `content_filter` can make thresholds stricter. Anything looser, or switching a filter off,
still needs Microsoft's approval and an ADR with the client (ADR 0006).

### 6. Pipeline roles
The Tier 1 pipeline identity may now also assign `Search Index Data Contributor` and `Search Service
Contributor` (ABAC condition in `modules/deployment-identity`). In a cell, each client's pipeline may
also assign `Storage Blob Data Reader` (seven roles in its condition instead of six).

## Consequences
- Every tier runs the same job code and settings; only who owns the identity and the index definition
  differs. In push mode every embedding token passes the gateway, so ingestion can't starve chat
  unnoticed, and showback separates it by caller.
- In Tier 2 the app can no longer write its index once its client has a job. A compromised app can
  still read its own client's data, but it can't poison what future answers are built from.
- A document carrying hidden instructions blocks every question that retrieves it, rather than
  steering the answer. That's the safe failure. The app should log which sources were in a blocked
  prompt, and the block rate per client is on the dashboard (ADR 0009), so the document gets found and
  removed.
- Tier 3's existing jobs move into the module with a `moved` block: no job is destroyed or recreated.
- New per-cell and per-pool identity and job, and one more step in onboarding: start `job-index-admin`.
- The ingestion entry point is application code. This repo runs it, gives it identities, and fixes its
  contract. Configs carry placeholder image digests until that image exists.

## Alternatives considered
- **Indexers everywhere (pull).** No code to own, but in shared tiers the search identity would reach
  every client's storage. Rejected for Tiers 2 and 3; kept as a Tier 1 option.
- **The app writes its own index.** One less identity, but the internet-facing component holds write
  on the data every answer comes from. Rejected.
- **Search Service Contributor for each client's job in shared tiers.** It can't be scoped to one index,
  so each client could delete or redefine every other client's index. Rejected.
- **Prompt Shields at the gateway only** (`llm-content-safety`). Useful as an early check, but optional
  and in preview there; the model's content filter applies to every call, whichever path it takes.
  Both can run.
