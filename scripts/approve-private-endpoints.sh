#!/usr/bin/env bash
# Approve private endpoint connections to a client's App Gateway, but only from that client's own
# subscriptions (ADR 0013). Everything else that is pending gets rejected.
#
#   scripts/approve-private-endpoints.sh <app-gateway-resource-id> <allowed-subscription-id> [...]
#
# The allowed subscriptions are client_connectivity.private_link.consumer_subscription_ids, also in
# `terraform output private_link_offer`. Needs az CLI signed in with rights on the App Gateway.
# Same thing by hand: portal > App Gateway > Private link > Private endpoint connections.
set -euo pipefail
agw_id="${1:?app gateway resource id}"; shift
[[ $# -gt 0 ]] || { echo "give at least one allowed subscription id" >&2; exit 2; }
allowed=" $(tr '[:upper:]' '[:lower:]' <<<"$*") "

conns=$(az network private-endpoint-connection list --id "$agw_id" -o json)
jq -c '.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending")' <<<"$conns" |
while read -r c; do
  id=$(jq -r .id <<<"$c")
  pe=$(jq -r .properties.privateEndpoint.id <<<"$c")
  sub=$(cut -d/ -f3 <<<"$pe" | tr '[:upper:]' '[:lower:]')
  if [[ "$allowed" == *" $sub "* ]]; then
    echo "approve  $pe"
    az network private-endpoint-connection approve --id "$id" --description "Approved: client subscription $sub (ADR 0013)" -o none </dev/null
  else
    echo "REJECT   $pe (subscription $sub is not this client's)"
    az network private-endpoint-connection reject --id "$id" --description "Rejected: subscription $sub not allowed for this client" -o none </dev/null
  fi
done
