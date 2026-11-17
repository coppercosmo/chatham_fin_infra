#!/usr/bin/env bash
# Approve the shared private links a Tier 1 client's AI Search service opened to its own storage account and
# model account (ingestion.mode = "pull", ADR 0015). Until they are approved the indexer can't reach either.
#
#   terraform output -json shared_private_links | scripts/approve-shared-private-links.sh
#
# Approves only Pending connections whose request message is the one Terraform set for this client's links;
# anything else pending on those resources is reported and left alone. Safe to re-run. Needs az CLI signed in
# with rights to approve private endpoint connections on the targets (the client's deployment identity has them).
# Same thing by hand: portal > storage account (or model account) > Networking > Private endpoint connections.
set -euo pipefail
links=$(cat)
[[ -n "$links" && "$links" != "{}" && "$links" != "null" ]] || { echo "no shared private links to approve"; exit 0; }

jq -c 'to_entries[] | .value' <<<"$links" |
while read -r link; do
  target=$(jq -r .target_resource_id <<<"$link")
  message=$(jq -r .request_message <<<"$link")
  conns=$(az network private-endpoint-connection list --id "$target" -o json </dev/null)
  approved=$(jq -r --arg m "$message" '[.[] | .properties.privateLinkServiceConnectionState | select(.status == "Approved" and (.description == $m or (.description // "" | startswith("Approved: AI Search indexer"))))] | length' <<<"$conns")
  while read -r c; do
    id=$(jq -r .id <<<"$c")
    if [[ "$(jq -r .properties.privateLinkServiceConnectionState.description <<<"$c")" == "$message" ]]; then
      echo "approve  $id"
      az network private-endpoint-connection approve --id "$id" --description "Approved: AI Search indexer for this client (ADR 0015)" -o none </dev/null
      approved=$((approved + 1))
    else
      echo "skip     $id (pending, but not this client's Search link: review it by hand)"
    fi
  done < <(jq -c '.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending")' <<<"$conns")
  echo "$target: $approved approved link(s) from this client's Search service"
done
