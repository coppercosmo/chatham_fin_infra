# ADR 0016: Regulatory compliance standards in Defender for Cloud, report-only at the AI Advisory MG

- Status: Proposed (to Platform Engineering, who own Defender for Cloud and Azure Policy; ADR 0002)
- Date: 2026-11-17
- Plain-words version, with the control mapping and per-tier queries: [compliance-standards.md](../architecture/compliance-standards.md)

## Context
Bank and insurer clients ask a vendor for evidence against named frameworks: SOC 2 first, then ISO 27001,
NIST, and regional rules such as DORA. Defender for Cloud can score Azure configuration against these
frameworks continuously, but only for the standards someone assigns, and only for the automated part of
each framework. Three things make it less simple than switching standards on:

- **Ownership.** P&T own Defender for Cloud and policy assignments (ADR 0002). Anything we propose has to fit
  their management group structure and must not interfere with their baseline.
- **Tenancy.** Defender reports per subscription or management group. That matches Tier 1 (a subscription
  per client) but not a shared cell or pool (ADR 0014).
- **The built-ins are uneven.** Checked against Microsoft's definitions on 2026-11-17: ISO/IEC 27001 2022 has
  58 checks mapped to clauses 6 to 10, mostly "Defender plan on" and logging; the EU AI Act and NIST AI RMF
  have 6 and 1; MCSB v2 is preview; the FFIEC retired its CAT on 2025-08-31; there is no built-in NYDFS
  Part 500 or ISO/IEC 42001 standard. MCSB ships its customer-managed-key checks disabled, while SOC 2, NIST
  and DORA audit them, so our known CMK gap shows under some standards and not others.

## Decision

1. **Assign once, at the AI Advisory management group.** `terraform/modules/compliance-standards` assigns
   SOC 2 Type 2, ISO/IEC 27001 2022 and NIST SP 800-53 Rev. 5 there by default, so the platform subscription
   and every client, cell and pool subscription inherit them, including ones vended later. MCSB stays
   P&T's assignment at their intermediate root and is not repeated.
2. **Report only.** Every assignment is DoNotEnforce, with a system-assigned identity (required when a
   standard contains DeployIfNotExists rules) that gets no roles. Standards score; the guardrails initiative
   (`policy-guardrails`) blocks; P&T's baseline deploys. Nothing a standard does can break a deployment.
3. **Per-client standards at the client's scope.** DORA, NIS2, NIST CSF 2.0, UK OFFICIAL and the rest are
   assigned per client through `scoped_standards`: at the client's subscription in Tier 1, at its resource
   group in a cell. A pool is one subscription, so a standard there covers every tenant.
4. **Per-client evidence by tier.** Tier 1: Defender's dashboard for the client's subscription. Tier 2: Azure
   Policy compliance filtered to the client's resource group and to shared resources (tag `client = shared`),
   from Resource Graph. Tier 3: the pool's report plus the isolation tests; Tier 3 holds only internal or
   public data.
5. **A verified catalog, with status.** The module accepts only standards in its catalog. Each entry has the
   built-in initiative GUID, the source file in Microsoft's repository, and a status (`ga`, `preview`, `thin`,
   `superseded`). The retired FFIEC CAT is refused estate-wide; NIST CSF 2.0 replaces it.
6. **Custom standards where no built-in exists.** `policy/standards/<name>.json` defines sections and the
   built-in audit checks that evidence them; the module builds an initiative with control groups and
   `metadata.ASC = "true"` so Defender shows it as a standard. The first is NYDFS Part 500 (technical
   subset, 18 checks, 7 sections). Process controls, ISO/IEC 42001 and the AI frameworks' non-technical
   obligations go to Purview Compliance Manager templates, not Defender.
7. **Accepted gaps are exemptions.** Known gaps (customer-managed keys first) are exempted per subscription
   with the same rules as the guardrails: a category, an expiry date and an ADR in the reason.
8. **Defender plans and AI settings we ask P&T for.** Defender CSPM (AI security posture, attack paths, and
   most of the ISO 27001 score), Defender for AI Services, Storage, Key Vault, Resource Manager, APIs, and
   Containers for AKS clients. **Suspicious prompt evidence** in AI alerts stays off unless a client agrees
   in writing, because it copies prompt content out of the client's own workspace (ADR 0009).

## Consequences
- One pull request to P&T gives every client subscription the same standards from day one; onboarding only
  touches compliance when a client needs an extra standard.
- Clients in Tier 1 get a clean, per-subscription report. Tier 2 reports need a Resource Graph export and a
  sentence explaining the shared resources. Tier 3 has no per-tenant score.
- Turning standards on will show red where the platform has known gaps (customer-managed keys) and where
  Defender plans are off. Both are visible and dated rather than hidden.
- A paid Defender plan is a prerequisite for any standard beyond MCSB, so cost sits with P&T's plan choices.
- The catalog will drift as Microsoft versions initiatives. The GUIDs are stable; the names and versions
  must be re-checked before quoting them to a client.
- The custom NYDFS mapping is our judgement, not Microsoft's or counsel's. It should be reviewed by Chatham's
  compliance team before a client sees it.

## Alternatives considered
- **Add standards per subscription in the portal.** Fast for one client, but every new subscription needs
  someone to remember, and nothing is reviewed or versioned. Rejected.
- **Assign standards in Default enforcement mode.** Some built-in policies allow Deny; enforcing a whole
  framework would block deployments for reasons nobody chose. Blocking stays a deliberate, per-rule decision
  in the guardrails. Rejected.
- **One large custom initiative instead of built-ins.** Full control, but loses Microsoft's control mapping and
  updates, and an auditor recognises the built-in names. Built-ins first; custom only for gaps.
- **Purview Compliance Manager only.** It covers process controls and the AI frameworks better, but doesn't
  scan Azure configuration continuously. Use both: Defender for configuration, Compliance Manager for the rest.
