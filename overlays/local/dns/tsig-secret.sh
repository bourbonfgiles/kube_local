#!/usr/bin/env bash
# Creates the TSIG key BIND accepts updates with. Kept out of Git; re-running
# leaves an existing key alone.
set -euo pipefail

CONTEXT="k3d-${1:-dev}"
k() { kubectl --context "${CONTEXT}" "$@"; }

if k -n dns get secret externaldns-tsig >/dev/null 2>&1; then
  SECRET="$(k -n dns get secret externaldns-tsig -o jsonpath='{.data.secret}' | base64 -d)"
else
  SECRET="$(openssl rand -base64 32)"
fi

k create namespace dns --dry-run=client -o yaml | k apply -f - >/dev/null
k -n dns create secret generic externaldns-tsig \
  --from-literal=secret="${SECRET}" \
  --from-literal=tsig.key="key \"externaldns\" { algorithm hmac-sha256; secret \"${SECRET}\"; };" \
  --dry-run=client -o yaml | k apply -f -
