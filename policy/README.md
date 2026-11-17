# Proposed AI guardrails (for Platform Engineering to own)

These are **proposals to P&T**, not policies we assign ourselves (ADR 0002). Each one codifies a
rule our stamp already follows, so assigning it at the `AI Advisory` management group costs us
nothing and protects against anyone deploying AI services outside the stamp.

| File | Effect | Why |
|---|---|---|
| `deny-cognitive-services-local-auth.json` | Deny AI services with API keys enabled | Keys get pasted into notebooks and tickets; managed identity can't be |
| `deny-cognitive-services-public-network.json` | Deny AI services with public network access | Client prompts must stay on private networking |
| `allowed-openai-deployment-skus.json` | Deny model deployments outside approved SKUs (e.g. GlobalStandard) | Data residency: prompts processed only in the approved data zone |
| `deny-paas-public-network-access.json` | Deny storage, Key Vault and AI Search with public network access | Same rule for the data stores that hold documents, chunks and secrets |
| `require-resource-group-tags.json` | Deny resource groups missing `client`, `cost_center`, `data_classification`, `owner` | Cost showback and data handling need to know whose resource it is |
| `inherit-tag-from-resource-group.json` | Modify: copy a tag from the resource group when a resource lacks it | Tags set once on the group reach every resource, including ones Terraform doesn't tag |
| `deploy-private-dns-zone-group.json` | DeployIfNotExists: register a private endpoint in P&T's central `privatelink.*` zone | Stamps in landing-zone mode never write DNS themselves; the hub zones stay P&T's |

Many of these exist as built-ins (search the portal for "Azure AI Services resources should have key
access disabled" and "... should restrict network access"); prefer the built-in where it exists
and use these custom definitions only for gaps such as deployment SKU.

## Deploying them: `terraform/modules/policy-guardrails`

A module P&T can run (or that we run in a sandbox management group to prove the rules) that turns this
folder into one initiative:

- every `*.json` here becomes a custom definition at `definition_management_group_id`;
- one initiative bundles them with the built-in **Allowed locations**, one tag-inheritance rule per
  required tag and one private-DNS rule per entry in `private_dns_zones`;
- the initiative is assigned at `assignment_management_group_id` (the AI Advisory MG) with a
  system-assigned identity, which gets exactly the roles the Modify and DeployIfNotExists rules
  declare (read from each definition's `roleDefinitionIds`) plus `Network Contributor` on the DNS zones;
- `enforce = false` (the default) assigns in **DoNotEnforce** mode: everything is evaluated and
  reported, nothing is denied. Roll out with `false`, read the compliance report, fix or exempt, then
  set `true`;
- `exemptions` are time-boxed: an expiry date is required and the reason must cite an ADR
  (`ADR 0014` and so on) in its `reason`, so every exception has a written reason and an end date.

```hcl
module "guardrails" {
  source                         = "../../modules/policy-guardrails"
  definition_management_group_id = "/providers/Microsoft.Management/managementGroups/chatham"
  assignment_management_group_id = "/providers/Microsoft.Management/managementGroups/ai-advisory"
  enforce                        = false # DoNotEnforce until the compliance report is clean
  private_dns_zones = {
    vault = { resource_type = "Microsoft.KeyVault/vaults", group_id = "vault", zone_ids = [local.zones.vault] }
    blob  = { resource_type = "Microsoft.Storage/storageAccounts", group_id = "blob", zone_ids = [local.zones.blob] }
  }
}
```

## Custom compliance standards: `policy/standards/`

Frameworks with no built-in Defender for Cloud standard, written as sections plus the built-in audit checks
that evidence them. `terraform/modules/compliance-standards` turns each file into an initiative with control
groups and `metadata.ASC = "true"`, so Defender shows it as a standard, and assigns it report-only at the
AI Advisory MG next to the built-in standards (ADR 0016).

| File | What |
|---|---|
| `standards/nydfs-part-500.json` | NYDFS 23 NYCRR Part 500, technical subset: 18 built-in checks across sections 500.3, .5, .6, .7, .14, .15 and .16. Our mapping, configuration only |

These files are not guardrails: the guardrails module reads only `policy/*.json`. Background, the full list of
standards and how our rules map to their controls: [compliance-standards.md](../docs/architecture/compliance-standards.md).

Offline tests: `cd terraform/modules/policy-guardrails && terraform test`. Plain-words background on
management groups, vending and policy effects: [landing-zones-and-policy.md](../docs/interview/deep-dives/landing-zones-and-policy.md).

