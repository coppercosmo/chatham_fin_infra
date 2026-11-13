# Talking point: triaging security scanner findings

**The story in one breath:** "When I turned on Checkov, it reported 22 findings. I didn't silence
them in bulk or chase a green badge. I sorted each one into *fix*, *false positive*, or *accepted
risk with a reason and an exit plan*. I fixed 6, wrote down why each of the other 16 was a false positive or an acceptable risk
right next to the code, and then made the scan blocking so nothing new gets in without the same
review."

## What changed

| Bucket | Count | Examples |
|---|---|---|
| **Fixed** | 6 | Azure OpenAI can now only call out to the client's own Search and blob hosts (exfiltration guard). AI Search runs 3 replicas so it meets Microsoft's read/write SLA. The container registry is zone-redundant, uses dedicated data endpoints, and purges untagged images after 7 days. |
| **False positive / not applicable** | 7 | Key Vault and storage private endpoints and blob logging *are* configured, but in the stamp or on the blob service, where the scanner can't follow. Queue logging doesn't apply because no queues are used. The offline `terraform test` suite asserts the private-endpoint guarantees instead. |
| **Accepted risk, with an exit plan** | 9 | Customer-managed keys: offered per client contract, not a default. ZRS instead of geo-replication by default, for data residency. The state account keeps a public endpoint (Entra ID auth only) until self-hosted runners exist. Docker Content Trust is being retired, so images are signed with Notation and deployed by digest. |

Also added along the way: a platform Log Analytics workspace that records who read or wrote
Terraform state and who pushed or pulled images.

## Why it matters (for a non-technical audience)
"A scanner gives you a to-do list, not a verdict. In financial services the auditor's question is
'show me you knew about it and decided'. Every exception is written next to the code it affects,
with the reason, and the build fails if someone adds a new one without that."

## Questions to expect
- *"Why not just turn on customer-managed keys everywhere?"* They add a key that someone must
  rotate and could lose, and they make destroy/restore harder. That's worth it when a client's
  contract asks for it, so it's a per-client option rather than a blanket default.
- *"Isn't skipping checks dangerous?"* A skip without a reason is. Each skip here names its
  reason and its exit condition, reviewers see it in the PR diff, and `checkov` lists every skip in
  its output, so they're auditable.
- *"How do you stop the list of exceptions from growing quietly?"* The scan is blocking, and a new
  `#checkov:skip` shows up in code review like any other change.
