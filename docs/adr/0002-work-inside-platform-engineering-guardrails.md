# ADR 0002: Build inside the central Platform Engineering landing zone

- Status: Accepted
- Date: 2026-11-13

## Context
Chatham's core Platform Engineering team (Product & Tech, "P&T") owns the Azure management group
hierarchy, Azure Policy, Entra ID groups, hub networking, and Defender for Cloud. They are
prescriptive by design. AI Advisory needs to move faster than tickets-to-P&T has allowed, but a
parallel shadow platform would be a security and political failure.

## Decision
We are a **landing-zone consumer**, not a second platform team. Concretely:

| Concern | Owned by P&T (we consume) | Owned by AI Advisory (this repo) |
|---|---|---|
| Management groups, subscription vending | Yes | We submit a standard request per client |
| Azure Policy (deny public endpoints, allowed regions, tagging, diagnostics) | Yes | Our stamp is designed to pass it with zero exemptions |
| Entra ID groups and PIM | Yes | We request a fixed set of groups per client and take their object IDs as inputs |
| Hub VNet, firewall, Private DNS zones, DNS resolver | Yes | Our spoke peers to the hub; DNS records come from P&T's DINE policy |
| Defender for Cloud, Sentinel | Yes | We send diagnostics to logs they can read |
| Everything inside a client subscription | | Yes |
| Shared AI Advisory platform subscription | | Yes |

The Terraform supports two connectivity modes so it can be developed before P&T integration is
ready, and run in a personal subscription for demos:

- `connectivity_mode = "landing_zone"`: no Private DNS zones are created; peering and DNS
  servers come from the hub; private endpoint DNS records are left to P&T's policy.
- `connectivity_mode = "standalone"`: the stamp creates and links its own Private DNS zones.

## How we work with P&T
1. **Ask for a contract, not tickets.** Agree the per-client vending request (subscription,
   management group, spoke CIDR from IPAM, Entra groups, budget owner) as a template with an SLA.
2. **Prove compliance in CI.** Run the same policy definitions P&T assigns (or `checkov` rules
   that mirror them) against our plans, so a pull request fails before Azure Policy does.
3. **Propose, don't fork.** AI-specific guardrails we want (e.g., deny local auth on Cognitive
   Services, allowed model deployment SKUs) are written as policy definitions in `policy/` and
   offered to P&T to own and assign.
4. **Exemptions are time-boxed and recorded** in an ADR, never silently applied.

## Consequences
- We can't create Entra groups or edit hub routes ourselves; inputs make that dependency explicit.
- P&T gains a repeatable consumer pattern instead of a stream of bespoke requests, which is the
  pitch that gets their buy-in.
