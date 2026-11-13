# ADR 0001: One Azure subscription per client

- Status: Accepted
- Date: 2026-11-13

## Context
AI Advisory is moving from one-off client builds to solutions built once and hosted for many
clients. The clients are financial-services firms (an insurance client is the first). One client's
data, prompts, or model outputs reaching another client is the worst possible outcome for the
practice, and for Chatham's reputation.

We need an isolation boundary that is:
- strong enough to explain to a client's security/vendor-risk team in one sentence,
- enforceable by Azure itself, not by our application code being bug-free,
- cheap enough to repeat for every new client, using automation.

## Options considered

| Option | Isolation | Ops cost | Notes |
|---|---|---|---|
| **A. Subscription per client** | Strong: RBAC, Policy, networking, quotas, cost, and Activity Log are all scoped to the subscription | Medium: needs subscription vending | Azure OpenAI quota (TPM) is per subscription per region, so a noisy client cannot starve another |
| B. Resource group per client in a shared subscription | Medium: RBAC and tags only; subscription-level roles, quotas, and policies are shared | Low | A subscription-scoped role assignment or a quota spike affects every client |
| C. Shared app, logical (row/tenant-ID) isolation | Weak: one bug or one bad query leaks data | Lowest | Hard to defend to a regulated client; cost attribution is guesswork |
| D. Separate Entra tenant per client | Strongest | Very high | Breaks central identity, Policy, and Defender; P&T would (rightly) reject it |

## Decision
**Option A.** Each client gets its own subscription, vended into an `AI Advisory / Clients`
management group that Platform Engineering owns. The subscription is a "stamp": the same
Terraform root module deploys the same shape for every client, with only a small config file
changing.

Things that hold no client data (container registry, Terraform state, CI identities) live in a
single shared `AI Advisory Platform` subscription. See [0007](0007-terraform-layout-and-state.md).

## Consequences
- Positive: a one-sentence answer to "how is our data isolated?". Cost per client comes free from
  billing scope. Quota, policy exemptions, and incident blast radius are per client. Offboarding is
  "export, then delete the subscription".
- Negative: we depend on P&T's subscription vending speed. Mitigation: agree a vending SLA and a
  pre-approved request template with P&T (see ADR 0002); keep a small pool of pre-vended,
  empty subscriptions ready.
- Negative: fixed per-client overhead (private endpoints, Log Analytics, Container Apps
  environment) of roughly a few hundred USD/month before usage. Acceptable for hosted
  enterprise engagements; priced into the client contract.
- Shared AI capacity (e.g., PTUs bought once and shared) is not possible across subscriptions.
  If that becomes a cost problem we revisit with a dedicated ADR rather than weakening isolation by default.

## How to explain it to a non-technical stakeholder
"Each client gets their own locked room in our building. Same floor plan, same locks, built by the
same robot, but no shared doors. If something goes wrong in one room, the others don't notice."
