# ADR 0011: AKS as a per-client hosting option

- Status: Accepted (amends ADR 0005)
- Date: 2026-11-15

## Context
ADR 0005 chose Container Apps as the default compute because a small team must run it in every
client subscription. Some client solutions will need what Container Apps can't do well:
- **self-hosted or fine-tuned open-weight models on GPUs** next to Azure OpenAI,
- heavy custom networking, sidecars, or a service mesh,
- Kubernetes-native tooling the client or Alex's team already standardises on (operators, KEDA
  scalers, Argo/Flux),
- a client that contractually requires a Kubernetes-based deployment.

## Isolation models for running many clients on AKS

| Model | What's shared between clients | Verdict |
|---|---|---|
| Namespace per client in one shared cluster | Control plane, nodes and kernel, cluster identity, CNI, ingress, cluster admins, upgrade windows | **Rejected.** "Soft" multi-tenancy: a container escape, a mis-scoped RBAC binding or a noisy neighbour crosses clients. Can't pass ADR 0001. |
| Node pool per client in one shared cluster | Control plane, cluster identity, CNI, cluster admins, upgrades | **Rejected.** Better kernel isolation via taints/affinity, but still one API server and one set of admins for every client's data. |
| Virtual clusters (vcluster) / Kata pod sandboxing | Underlying cluster | Interesting for internal/dev tenancy; not a regulator-friendly story for client data. |
| **Dedicated cluster per client, in the client's subscription** | Nothing | **Chosen.** Same boundary as every other resource in ADR 0001. |

## Decision
`compute_platform` is a per-client switch in the stamp: `container_apps` (default) or `aks`.
Everything else in the stamp (network, AOAI, Search, Key Vault, storage, identity, ingress, logs) is
identical, so changing a client's compute is a contained change, not a re-platform.

The `terraform/modules/aks` cluster:

| Area | Setting | Why |
|---|---|---|
| API server | **Private cluster**, no public FQDN; private DNS zone is AKS-managed (standalone) or P&T's `privatelink.<region>.azmk8s.io` (landing zone) | Control plane unreachable from the internet |
| Authn/z | **Entra ID only, local accounts disabled, Azure RBAC for Kubernetes**; admins are a P&T PIM-eligible group; readers get `AKS RBAC Reader` | Same identity model as the rest of Azure; no kubeconfig certs to leak |
| Workload identity | OIDC issuer + workload identity. The client's existing app identity gets a **federated credential for one service account in this cluster** | Pods use the same least-privilege identity as Container Apps would; no secrets in pods |
| Network | **Azure CNI Overlay + Cilium dataplane + Cilium network policy**; nodes in `snet-aks` (/24), pods in a non-routable overlay CIDR | IP-efficient (a /24 serves the cluster), eBPF dataplane, default-deny policies |
| Egress | `userDefinedRouting` through the hub firewall in landing-zone mode | Same inspected egress as Container Apps |
| Ingress | Managed NGINX (app routing add-on) on an **internal LB with a static IP**, fronted by the per-client App Gateway WAF (ADR 0010); cert from Key Vault | One ingress/WAF pattern for both compute options |
| Secrets | Key Vault Secrets Store CSI driver with rotation | Secrets stay in the client vault |
| Guardrails | **Azure Policy add-on** (Gatekeeper) | P&T's policies (e.g., no privileged pods, allowed registries) apply *inside* the cluster too |
| Node pools | `system` (critical add-ons only, 3 zones), `user` for apps, optional `gpu` (tainted, scale from 0) | Isolates system pods; GPUs cost nothing when idle |
| Nodes | Azure Linux, ephemeral OS disks, **host encryption** | Smaller attack surface, faster reimage, encryption at rest for temp/cache |
| Images | User-assigned kubelet identity with `AcrPull` on the shared ACR, granted **before** the cluster exists | No first-deploy race; no registry credentials |
| Upgrades | `patch` auto-upgrade channel, weekly `NodeImage`, Sunday maintenance window, image cleaner | Patches without a human, inside an agreed window |
| Ops | Standard tier (API SLA), Container Insights to the client workspace, `kube-audit` diagnostics | Same per-client observability as ADR 0009 |
| Deploys | **Flux (AKS GitOps extension)** reconciles `kubernetes/` per client | CI never needs network access to a private API server |

### Ingress for AKS: why not AGIC or Application Gateway for Containers?
- **AGIC** lets an in-cluster controller rewrite the App Gateway. That splits ownership of the
  gateway between Terraform and the cluster (drift, surprise changes), and AGIC is the older model.
- **Application Gateway for Containers** is Microsoft's direction for AKS ingress and is attractive
  for AKS-only estates. We'd revisit it when its private-frontend and WAF capabilities match what
  ADR 0010 requires. Even then it wouldn't cover Container Apps clients, so we'd run two ingress patterns.
- **Chosen**: App Gateway WAF_v2 (Terraform-owned) -> internal managed NGINX. One WAF, cert and log
  model for every client regardless of compute.

## When to choose which

| Signal | Container Apps | AKS |
|---|---|---|
| Stateless API + workers using Azure OpenAI | Yes | Overkill |
| Self-hosted / fine-tuned model on GPUs | Serverless GPUs possible but limited | **Yes** |
| Team needs Kubernetes operators, mesh, custom CRDs | No | **Yes** |
| Fixed monthly cost per client | Low (scale to zero) | Higher: 3 system + 2 user nodes minimum (roughly USD 1,000+/month before GPUs) |
| Ops load on a small team | Low | Medium: upgrades are automated, but there's more to understand when something breaks |

## Consequences
- Two compute paths to support. Mitigated by keeping everything else in the stamp identical and by
  making AKS opt-in per client with a written reason in the client's config.
- Extra assignable roles for the pipeline identity (Network Contributor, Private DNS Zone
  Contributor, Managed Identity Operator, AKS RBAC Reader). Still constrained by the ABAC condition (ADR 0004).
- In landing-zone mode, the control-plane identity needs `Private DNS Zone Contributor` on P&T's
  `azmk8s.io` zone in the connectivity subscription. That grant is P&T's to make (onboarding runbook).
- The app team ships a container either way. Only the deployment manifest differs (Container App
  resource vs `kubernetes/app.yaml`).
