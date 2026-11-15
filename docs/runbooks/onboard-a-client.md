# Runbook: onboard a new client

Target: a new client environment from "contract signed" to "app reachable" in **under a day of
engineering time** (elapsed time depends on P&T vending and AOAI quota).

## 1. Request from P&T (standard template)
- [ ] Subscription in `AI Advisory / Clients` MG, name `sub-aiadv-<client>-prd`
- [ ] Spoke CIDR from IPAM (default /22)
- [ ] Entra groups: `sg-aiadv-<client>-readers`, `sg-aiadv-<client>-operators` (PIM-eligible)
- [ ] Budget owner and cost center
- [ ] Hub peering accepted on the hub side, firewall rules for required egress

## 1b. Ingress prerequisites (ADR 0010)
- [ ] Host name `<client>.ai.<domain>` and its certificate (from P&T's CA process or Key Vault's
      integrated CA); import it into the client vault after the first apply, then set the
      versionless secret ID in `ingress.certificate_secret_id`
- [ ] Decide `frontend_mode`: private (default) or public with the client's egress CIDRs
- [ ] P&T: DNS record to the gateway's private IP (`x.x.2.10`) or Front Door Private Link setup
- [ ] Subscription feature for private-only App Gateway deployment registered (vending template)

## 1c. AKS only (ADR 0011)
- [ ] Written reason for AKS in the client config (GPU, operators, client requirement)
- [ ] P&T: `sg-aiadv-<client>-aks-admins` group (PIM-eligible)
- [ ] P&T: `Private DNS Zone Contributor` on `privatelink.<region>.azmk8s.io` for the cluster's
      control-plane identity (output after a targeted apply of the identity)
- [ ] GPU quota in the region if `aks.gpu_pool` is set
- [ ] Flux configuration pointing at the client's rendered `kubernetes/` overlay

## 2. Request quota
- [ ] Azure OpenAI quota for each model in `terraform.tfvars` in the target region and SKU
- [ ] Note any data-residency or abuse-monitoring requirements from the client contract

## 3. Add the client to the platform layer
- [ ] Add the client to `terraform/platform/terraform.tfvars` `clients` map (creates
      `id-deploy-<client>`, the federated credential, and its constrained role assignment)
- [ ] PR, review, apply `platform`

## 4. Add the client config
- [ ] `cp -r terraform/clients/_template terraform/clients/<client>` and fill in values
- [ ] Create GitHub Environment `client-<client>` with variable `AZURE_CLIENT_ID`
      (output of step 3) and set reviewers for its ring
- [ ] Open a PR: CI plans only this client. Review the plan, merge, ring rollout applies it

## 5. Verify
- [ ] `nslookup <oai>.openai.azure.com` from inside the spoke resolves to a `10.x` address
- [ ] Calling any client endpoint from the internet fails (public access disabled)
- [ ] App health endpoint returns 200 through P&T ingress
- [ ] Logs visible in the client workspace; client appears in the central workbook
- [ ] Budget alert recipients confirmed
