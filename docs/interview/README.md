# Interview prep

Study material for the Senior Platform Infrastructure Engineer (AI Advisory) technical rounds. Everything
links back to the design (ADRs, diagrams) and the Terraform in this repo, so answers can point at
something real.

## Suggested order

1. [Topic map](topic-map.md): every topic from the recruiter notes, where it lives in the repo, and the
   30-second answer. Read first, then use it as a checklist.
2. [Isolation tiers](../architecture/isolation-tiers.md): the cost question everyone asks about
   subscription-per-client, and the two cheaper designs.
3. Deep dives ([index](deep-dives/README.md)):
   [data isolation for AI](deep-dives/data-isolation-for-ai.md),
   [observability per client](deep-dives/observability-per-client.md),
   [landing zones and policy](deep-dives/landing-zones-and-policy.md),
   [DR and capacity](deep-dives/dr-and-capacity.md).
4. [Likely questions](likely-questions.md): Q&A for ingress, AKS, the AI gateway and client networks.
5. [Mock technical test](practice/mock-technical-test.md): Terraform, networking, identity, design
   scenarios and debugging, with model answers and a from-scratch exercise
   ([`terraform/exercises/vnet-private-endpoint`](../../terraform/exercises/vnet-private-endpoint)).
6. [Two-minute repo walkthrough](repo-walkthrough.md), plus "what I'd do differently at scale".
7. [AI coding tools](ai-coding-tools.md) and [security scanning](security-scanning.md): how the repo was
   built and how findings were triaged.
8. [30-60-90 plan](30-60-90.md) for the final round.
