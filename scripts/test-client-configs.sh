#!/usr/bin/env bash
# Type-check every real client config against the stamp with a mocked provider (no Azure access).
# Generates one throwaway test file per client, reusing the mocks from tests/isolation.tftest.hcl.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stamp="$root/terraform/stamps/client"
mocks="$(sed '/^variables {/,$d' "$stamp/tests/isolation.tftest.hcl")"
trap 'rm -f "$stamp"/tests/client_*.tftest.hcl' EXIT

for dir in "$root"/terraform/clients/*/; do
  c="$(basename "$dir")"; [[ "$c" == _template ]] && continue
  {
    echo "$mocks"
    echo "run \"plan_${c}\" {"
    echo "  command = plan"
    echo "  variables {"
    cat "$dir/terraform.tfvars"
    echo "  }"
    echo "}"
  } > "$stamp/tests/client_${c}.tftest.hcl"
done

cd "$stamp"
terraform test
