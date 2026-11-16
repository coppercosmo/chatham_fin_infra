#!/usr/bin/env bash
# Run each stamp's offline tests and type-check every real config against it with a mocked
# provider (no Azure access). Generates one throwaway test file per config, reusing the mocks
# from that stamp's test file:
#   terraform/clients/<client>/terraform.tfvars        -> stamps/client       (Tier 1, dedicated)
#   terraform/cells/<cell>/terraform.tfvars            -> stamps/cell         (Tier 2, shared cell)
#   terraform/cells/<cell>/clients/<client>.tfvars     -> stamps/cell-client  (Tier 2, per-client RG)
#   terraform/pools/<pool>/terraform.tfvars            -> stamps/pool         (Tier 3, pooled)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stamps="$root/terraform/stamps"
trap 'rm -f "$stamps"/*/tests/config_*.tftest.hcl' EXIT

# check <stamp> <mock test file> <config file>...
check() {
  local stamp="$stamps/$1" mocks name f
  mocks="$(sed '/^variables {/,$d' "$stamp/tests/$2")"
  shift 2
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    name="$(realpath --relative-to="$root/terraform" "$f" | tr '/.-' '___')"
    {
      echo "$mocks"
      echo "run \"plan_${name}\" {"
      echo "  command = plan"
      echo "  variables {"
      cat "$f"
      echo "  }"
      echo "}"
    } > "$stamp/tests/config_${name}.tftest.hcl"
  done
  echo "== $(basename "$stamp")"
  (cd "$stamp" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color && terraform test)
}

shopt -s nullglob
clients=()
for dir in "$root"/terraform/clients/*/; do
  [[ "$(basename "$dir")" == _template ]] && continue
  clients+=("$dir/terraform.tfvars")
done
check client      isolation.tftest.hcl   "${clients[@]}"
check cell        cell.tftest.hcl        "$root"/terraform/cells/*/terraform.tfvars
check cell-client cell_client.tftest.hcl "$root"/terraform/cells/*/clients/*.tfvars
check pool        pool.tftest.hcl        "$root"/terraform/pools/*/terraform.tfvars
