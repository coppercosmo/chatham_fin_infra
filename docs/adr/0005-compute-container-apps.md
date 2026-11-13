# ADR 0005: Azure Container Apps (internal) as default compute

- Status: Accepted
- Date: 2026-11-13

## Context
Client solutions are mostly API + web front end + background workers (ingestion, evaluation).
The team is small; whatever we pick, we run it across every client subscription.

| Option | Fit | Per-client ops cost |
|---|---|---|
| **Container Apps (workload profiles, internal)** | Containers, scale-to-zero, jobs, Dapr, VNet integration, managed identity | Low: no cluster upgrades |
| App Service (Premium v3 + VNet integration) | Simple web apps | Low, but weaker for workers/jobs and sidecars |
| AKS (private cluster) | Maximum control, GPU, service mesh | High: N clusters to upgrade, patch, and secure |

## Decision
Container Apps with a workload-profiles environment, `internal_load_balancer_enabled = true`, in
`snet-apps`. Container Apps Jobs for ingestion/evaluation batch work.

**Revisit (new ADR) if** a client needs self-hosted models on GPUs, very custom networking, or
we reach a scale where a shared multi-client AKS is cheaper. Even then, a shared cluster would
break ADR 0001, so the default answer would be "AKS per client subscription" for that client only.

## Consequences
- Upgrades, node patching, and ingress controller management are Microsoft's job.
- Workload profiles subnet can be as small as /27; we use /24 for headroom.
- An internal environment needs a Private DNS zone for its default domain (`*.<env-domain>` to the
  environment's static IP). The stamp creates this zone and links it to the spoke.
