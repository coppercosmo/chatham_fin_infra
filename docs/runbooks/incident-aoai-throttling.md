# Runbook: Azure OpenAI throttling (HTTP 429) for a client

**Alert**: `aoai-429-rate` fired for `<client>`.

1. Scope: open the client's App Insights, filter dependencies to the AOAI host. Is it one
   deployment (model) or all? One app path or all?
2. Check current TPM usage vs. quota in the AOAI metrics blade (`ProcessedPromptTokens`,
   `GeneratedTokens`) for that client's subscription only. Other clients are unaffected by design.
3. Short-term options, in order:
   - Confirm the app retries with backoff and honors `retry-after`.
   - Pause or slow the client's ingestion/evaluation job (Container Apps Job) if it's competing.
   - Raise the deployment's `capacity` in `terraform.tfvars` (up to approved quota), PR, apply
     for that client only.
4. Longer-term: request more quota, or move a hot model to provisioned throughput for that client.
5. Tell the engagement lead in plain language: what users saw, why, what we changed, when it's fixed.
