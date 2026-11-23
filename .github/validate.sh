#!/usr/bin/env bash
# Offline check of what Flux would apply: build every Kustomization in
# clusters/dev with its own postBuild variables, then validate the result
# against Kubernetes and CRD schemas. Chart output and values aren't checked.
set -euo pipefail
cd "$(dirname "$0")/.."

catalog='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
status=0

for file in clusters/dev/*.yaml; do
  for ks in $(yq -N 'select(.kind == "Kustomization") | .metadata.name + ":" + .spec.path' "$file"); do
    name="${ks%%:*}"
    ks_path="${ks#*:}"
    echo "== $name ($ks_path)"
    if ! flux build kustomization "$name" --path "$ks_path" \
      --kustomization-file "$file" --dry-run >"$out/$name.yaml"; then
      status=1
      continue
    fi
    kubeconform -strict -summary \
      -schema-location default -schema-location "$catalog" \
      "$out/$name.yaml" || status=1
  done
done

exit "$status"
