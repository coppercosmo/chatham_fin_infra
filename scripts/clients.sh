#!/usr/bin/env bash
# Emit a JSON array of client codes for a GitHub Actions matrix.
#   scripts/clients.sh all               every client except _template and retired
#   scripts/clients.sh ring <n>          clients in ring n
#   scripts/clients.sh changed <base>    clients affected by changes since <base>
#                                        (a module/stamp change affects every client)
set -euo pipefail
cd "$(dirname "$0")/../terraform/clients"

all() {
  for f in */client.json; do
    c="${f%%/*}"; [[ "$c" == _template ]] && continue
    [[ "$(jq -r .ring "$f")" == retired ]] && continue
    echo "$c"
  done
}

case "${1:-all}" in
  all) all ;;
  ring) for c in $(all); do if [[ "$(jq -r .ring "$c/client.json")" == "$2" ]]; then echo "$c"; fi; done ;;
  changed)
    files=$(git diff --name-only "$2"...HEAD)
    if grep -qE '^terraform/(modules|stamps)/' <<<"$files"; then all
    else grep -oE '^terraform/clients/[^/]+' <<<"$files" | cut -d/ -f3 | sort -u | grep -vx _template || true
    fi ;;
  *) echo "usage: $0 all|ring <n>|changed <base>" >&2; exit 2 ;;
esac | jq -R . | jq -sc .
