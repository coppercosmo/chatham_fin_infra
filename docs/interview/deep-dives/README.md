# Deep dives

Short explainers for the topics most likely to come up in the technical interview, each with plain-words
definitions, how this repo handles it, and model answers. Read them in this order:

| # | Topic | What you should be able to explain afterwards |
|---|---|---|
| 1 | [Isolation tiers and cost](../../architecture/isolation-tiers.md) | Dedicated vs shared cell vs pooled; what each costs at 200 clients; which client gets which tier |
| 2 | [The AI layer, end to end (RAG)](ai-architecture.md) | The request flow from question to cited answer; ingest, retrieve, generate; isolation of the AI layer per tier; PTU vs pay-as-you-go; evaluations; content safety. Start here if the AI side is new |
| 3 | [Data isolation for AI](data-isolation-for-ai.md) | Where documents, chunks, prompts, history and logs live; what Microsoft does with prompts; CMK; residency |
| 4 | [Observability per client](observability-per-client.md) | Workspace per client vs shared; token showback through the gateway; alerts that gate rollout rings |
| 5 | [Landing zones and policy](landing-zones-and-policy.md) | The ALZ management group tree; subscription vending; Deny vs Modify vs DeployIfNotExists; safe rollout |
| 6 | [DR and capacity](dr-and-capacity.md) | RTO/RPO per tier; model failover through the gateway; pay-as-you-go vs PTU; capacity planning |

Then practise with the [mock technical test](../practice/mock-technical-test.md) and the
[repo walkthrough](../repo-walkthrough.md).
