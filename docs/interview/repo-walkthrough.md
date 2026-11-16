# Two-minute repo walkthrough

For "tell us about something you built" or "walk us through this repo". About 300 words, which is two
minutes at a calm pace. Practise it with a timer, out loud, with the repo open on screen.

## The script

| On screen | Say |
|---|---|
| README, the Mermaid picture at the top | "This is a reference platform for exactly the problem in the job description: building AI solutions once and hosting them for many financial-services clients on Azure, with each client's data isolated, inside a central platform team's landing zone rather than around it." |
| `docs/adr/` index | "I started with decisions, not code. Fourteen short ADRs. The big one is tenancy: by default every client gets its own subscription, because that boundary is enforced by Azure, not by our code, and it's one sentence to a client's risk team." |
| `docs/architecture/isolation-tiers.md`, the side-by-side table | "That's expensive at scale, roughly 1,500 dollars a month per client before tokens. So there are two cheaper tiers. A shared cell shares the front door, compute and AI gateway, but each client keeps its own storage, index, model account, keys, logs and identities, about 170 a client. A pooled tier, for internal or public data, is about 45 a tenant, and even there the app has no data access of its own: it reads with the user's token, so Azure checks every request." |
| `terraform/stamps/` and `terraform/modules/` | "Every tier is a Terraform root built from the same modules: private endpoints only, keys disabled, managed identities, per-client App Gateway WAF and an API Management AI gateway for token limits and metering." |
| `terraform/stamps/cell/tests/cell.tftest.hcl` | "Each root has offline tests with a mocked provider that assert the isolation rules for every client, like 'each client's API can only call its own model as its own identity'. CI runs them with tflint and Checkov on every pull request." |
| `.github/workflows/terraform-deploy.yml` | "Deployment is ring-based: our own internal client, then pilots, then everyone, each job with an OIDC identity that can only reach its own client." |
| `policy/` | "And the guardrails I'd expect Platform Engineering to own, like no public endpoints and data-zone model deployments, are written as policies I'd propose to them, with a module to roll them out in audit mode first." |
| Back to README, known gaps | "It isn't applied to a live tenant yet, and the README lists the known gaps honestly, like customer-managed keys and alerting." |

Stop there. Let them pick what to dig into.

## If they ask "what would you do differently at scale?"

Pick two or three, not all of them:

1. **Split modules into their own repo with versions.** Today modules and stamps share a repo, so the
   version is the commit. At 200 clients I'd publish modules with semantic versions and let roots
   upgrade deliberately, so a module change doesn't plan against every client at once.
2. **Make onboarding a pull request generated from a form.** Today it's three PRs for a cell client and
   a vending request for Tier 1. A small service or workflow that takes the client's tier, data
   classification and network and opens the PRs would cut errors and time.
3. **Apply in parallel with guardrails.** Hundreds of states means many parallel jobs; I'd add
   concurrency limits, a stop-the-line rule on the first failure in a ring, and alert-based gates
   between rings (the observability deep dive describes them).
4. **Close the known gaps first:** customer-managed keys (needs self-hosted runners inside the network),
   metric alerts from ADR 0009, Azure Monitor Private Link Scope, and model failover pools through
   `azapi` until the provider supports them.
5. **Ask P&T about the cheaper tiers early.** Tier 2 needs two narrow custom roles and their view of
   what counts as "isolated enough". That conversation decides how much of the saving is real.
6. **Measure before optimising.** Token metrics per client from the gateway tell you who should be on
   PTU, who could move to a cheaper tier, and what to charge.

## Likely follow-ups and short answers

- **"Why Container Apps and not AKS?"** Less to run for a small team, internal environments, scale to
  zero, managed identity built in. AKS is a per-client option (ADR 0011) when a client needs GPUs or
  Kubernetes operators.
- **"Why an API Management gateway in front of the models?"** One place for token limits per caller,
  token metering for showback, failover between deployments, and logging rules, without every app
  implementing them (ADR 0012).
- **"How long to onboard a client?"** Under a day of engineering for Tier 1, but elapsed time depends
  on P&T's vending and model quota. Hours for a cell client, same day for a pooled tenant.
- **"What was hardest?"** Making the cheaper tiers genuinely secure rather than just cheap: for example,
  the pooled app reading data with the user's own token, and each cell client's pipeline being able to
  grant only six specific roles in its own resource group.
- **"How did you use AI tools to build it?"** See [ai-coding-tools.md](ai-coding-tools.md): drafted
  with an assistant, every change through the same checks (fmt, validate, tflint, Checkov, tests), and
  reviewed by me. Have one concrete example ready of a suggestion you rejected and why.
