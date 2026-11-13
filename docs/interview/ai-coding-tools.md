# How AI coding tools were used here (fill in with your own specifics)

> Personalize this before the interview. The recruiter called AI coding tools a must-have; be
> concrete about tools, daily use, and review.

**Tools**: e.g., Claude Code in the terminal for multi-file work; Copilot/Cursor for in-editor completion.

**How this repo was built**
1. Started from decisions, not code: had the assistant draft ADRs, then challenged each trade-off.
2. Generated modules one at a time against the ADRs.
3. Verified, didn't trust:
   - `terraform validate` against the pinned provider caught deprecated arguments
     (e.g., `enable_rbac_authorization` -> `rbac_authorization_enabled`).
   - `terraform test` with a mocked provider asserts security properties (no public access, no
     keys, DNS ownership by mode) and type-checks every real client config.
   - Manually reviewed every role assignment and the ABAC condition against Microsoft docs.
4. Guardrails for AI-written IaC in a team: same PR checks for everyone (human or AI), checkov
   policy-as-code, required reviewers, never let an assistant hold apply credentials.

**What I'd say**: "AI makes the first draft fast; my job is the review, the tests that prove the
security properties, and owning the decision."
