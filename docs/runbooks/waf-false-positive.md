# Runbook: WAF is blocking legitimate requests

**Symptom**: users of `<client>` get HTTP 403 from the gateway; the app never sees the request.

1. Find the blocked requests in the client's Log Analytics:
   ```kusto
   AGWFirewallLogs
   | where TimeGenerated > ago(1h) and Action == "Blocked"
   | summarize count() by RuleId, Message, DetailedMessage, RequestUri
   | order by count_ desc
   ```
   (Older workspaces in Azure Diagnostics mode use `AzureDiagnostics | where Category == "ApplicationGatewayFirewallLog"`.)
2. Decide whether it's an attack or a false positive. Look at the matched value (`DetailedData`) and
   the source IP. Most LLM false positives are SQLI (942xxx) or XSS (941xxx) rules matching natural
   language or pasted HTML in a prompt field.
3. If it's a prompt field we don't exclude yet (e.g., the app added `context`), add it to
   `ingress.waf_prompt_field_exclusions` for that client. It's excluded only from the SQLI/XSS groups.
4. If it's one specific rule on one specific path, add a **narrow** exclusion or a per-URI policy.
   Never switch the whole policy to Detection in a production ring.
5. Ship it like any change: PR (plan shows only the WAF policy changing), ring rollout.
6. Tell the engagement lead in plain language: what was blocked, why, what changed.

**New clients**: run ring 0 / first week in `waf_mode = "Detection"`, review the log above daily,
then switch to Prevention.
