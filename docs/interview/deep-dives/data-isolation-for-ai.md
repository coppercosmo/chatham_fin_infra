# Data isolation for AI workloads

What client data an AI app creates, where each piece lives in this design, and what Microsoft does
with prompts. Related: [ADR 0006](../../adr/0006-azure-openai-per-client.md) (model accounts),
[isolation tiers](../../architecture/isolation-tiers.md), [ADR 0009](../../adr/0009-observability-per-client.md) (logs).

## The short version

An AI app doesn't just have "the documents". It creates several copies and derivatives of client data,
and each one needs a home with the right boundary:

| Data | What it is | Where it lives here | Boundary |
|---|---|---|---|
| Source documents | PDFs, spreadsheets the client uploads | Client's storage account (Tier 1/2) or the tenant's blob container (Tier 3) | Separate account per client, or container-scoped role checked against the user's token |
| Chunks and embeddings | Pieces of the documents and their vectors, for retrieval (RAG) | Client's search index | Index per client; `Search Index Data Reader/Contributor` scoped to that index |
| Prompts and completions in flight | The question, the retrieved chunks, the answer | Processed by the client's own Azure OpenAI account (Tier 1/2) or the pool's (Tier 3), in the data zone | Private endpoint, keyless, per-client identity |
| Conversation history | Previous turns, if the app keeps them | The client's own storage, never the model service | Same as source documents |
| Logs and telemetry | Requests, errors, token counts, sometimes prompt fragments | Client's Log Analytics workspace and App Insights | Workspace per client; gateway body logging off by default |
| Keys | Encryption keys, TLS certificates | Client's Key Vault | Vault per client, RBAC, purge protection |

The rule behind every row: **anything that stores client data is per client, keyless, private, and
reachable only by that client's identities** (or, in Tier 3, by that tenant's users).

## What Microsoft does with prompts (Azure OpenAI)

Interviewers in financial services often ask this. The answer, from Microsoft's "Data, privacy, and
security for Azure OpenAI" documentation:

- Prompts, completions, embeddings and your training data are **not available to other customers**,
  **not available to OpenAI**, and **not used to train or improve** OpenAI's or Microsoft's models.
- The models are stateless: a chat or embeddings call doesn't store the prompt in the model.
- **Abuse monitoring:** by default, Microsoft may store prompts and completions that its classifiers
  flag, in the same geography as the resource, and authorised Microsoft staff may review them.
  Customers who are approved through the **modified abuse monitoring** process (a Limited Access
  application) can turn this off. You confirm it in the resource's properties: the capability
  `ContentLogging` shows `false`. ADR 0006 tracks this per client.
- **Some features store data at rest** in the resource's geography: the Responses API (it stores
  responses unless the call says `store: false`), Assistants and threads, stored completions, files,
  vector stores, batch jobs and fine-tuning. Those are fine in a dedicated account (Tier 1/2) and
  ruled out in the shared pool account (Tier 3).
- **Deployment type decides where prompts are processed.** `Global*` can process in any Azure
  geography; `DataZone*` stays within the US or EU data zone; regional `Standard` stays in the region.
  Data at rest stays in your geography in all cases. We default to `DataZoneStandard` and the policy
  `allowed-openai-deployment-skus.json` blocks `GlobalStandard`.

## Customer-managed keys (CMK)

By default Azure encrypts storage, search and the model account with Microsoft-managed keys. A
customer-managed key in the **client's own Key Vault** adds two things a regulated client may ask for:
the client can see every use of the key, and **deleting or disabling the key makes the data unreadable**
(crypto-shredding), which is a clean offboarding story.

How it fits the tiers:
- **Tier 1 and 2:** one key per client in that client's vault, used by its storage account, search
  index and AI services account. Needs purge protection on the vault and a user-assigned identity
  with `Key Vault Crypto Service Encryption User` on the key.
- **Tier 3:** one storage **encryption scope** per tenant, optionally backed by a tenant-specific key
  (`cmk_key_id` in the pool's `tenants` map).

Honest status in this repo: CMK is a known gap for Tiers 1 and 2. Creating a key is a Key Vault
**data-plane** call, which needs network line of sight to a private vault, so it needs self-hosted
runners inside the network (or creating the key through the ARM control plane). The README lists this.

## Data residency

Three choices decide where data lives: the **region** of each resource (policy: *Allowed locations*),
the **deployment type** of each model (data zone, not global), and the **workspace region** for logs.
A client that requires single-region processing gets regional `Standard` or provisioned deployments,
which is a Tier 1 decision.

## Prompt injection and cross-client leakage

The model can be talked into ignoring instructions, so never rely on the prompt for isolation. In this
design the model only ever sees chunks retrieved from **that client's** index, with **that client's**
identity (or user token). Even a fully successful prompt injection can only reach data that identity
can already read. Tools that call other systems follow the same rule: they run with the client's
identity, never a shared one.

## Offboarding

- Tier 1: delete the subscription's resources (P&T cancels the subscription).
- Tier 2: delete the client's resource group (remove the locks first), remove its slot from the cell.
- Tier 3: remove the tenant from the map: container, index, encryption scope, identity and job go.
  With a tenant key, delete the key too, so any copy left in backups is unreadable.
- Logs follow their workspace's retention. Keep a written record of what was deleted and when.

## Interview questions and answers

**"Does Microsoft or OpenAI train on our clients' prompts?"**
No. Prompts and completions aren't shared with OpenAI or other customers and aren't used to train
models. The one thing to know is abuse monitoring: by default flagged content can be stored in the
resource's geography for human review. For clients who need it, we apply for modified abuse
monitoring and verify `ContentLogging` is false on their account.

**"Where would chat history live?"**
In the client's own storage, written by the client's app identity. Not in the model service's stateful
features, at least not in any shared account, so deleting the client's storage deletes their history.

**"How do you make sure a RAG answer for client A never includes client B's documents?"**
Separate indexes and separate identities. A's app (or A's user token) only has a role on A's index, so
B's chunks can't be retrieved, whatever the prompt says. I wouldn't use one shared index with a tenant
filter, because then a missing filter in code is a leak.

**"What's the difference between Global, DataZone and Standard deployments?"**
Where the prompt can be processed: anywhere, within the US or EU zone, or within one region. Data at
rest stays in your geography in all three. We default to DataZone for capacity with residency, and
block Global by policy.

**"How would you add customer-managed keys?"**
A key per client in their vault, with purge protection, used by storage, search and the AI services
account through a user-assigned identity. The practical catch is that creating the key is a data-plane
call to a private vault, so the pipeline needs a runner inside the network or a control-plane path.
