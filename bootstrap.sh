#!/usr/bin/env bash
# One-time imperative bootstrap for the CNI-less k3d "dev" cluster.
#
# The cluster boots with no CNI (flannel + kube-proxy disabled), so nodes are
# NotReady until Cilium is installed. Cilium and Flux cannot be installed BY
# Flux (Flux is pods; pods need a CNI), so they go on here. Everything else is
# declared in Git and reconciled by Flux.
#
# Cilium is installed with the same chart and values that the Flux HelmRelease
# uses (infrastructure/cilium), so Flux adopts this release instead of fighting
# it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="${REPO_ROOT}/infrastructure/cilium/release.yaml"
CILIUM_VERSION="1.18.1"

helm repo add cilium https://helm.cilium.io >/dev/null
helm repo update cilium >/dev/null

# Install with the exact values the Flux HelmRelease declares (inline under
# spec.values) so Flux adopts this release rather than fighting it.
yq eval 'select(.kind == "HelmRelease") | .spec.values' "${RELEASE}" \
  | helm install cilium cilium/cilium \
      --version "${CILIUM_VERSION}" \
      --namespace kube-system \
      --values -

cilium status --wait
kubectl apply -f "${REPO_ROOT}/infrastructure/cilium/lb-ipam.yaml"

# Needs GITHUB_USER and GITHUB_TOKEN. Writes Flux manifests to clusters/dev and
# starts reconciling; Flux then owns Cilium via the HelmRelease.
flux bootstrap github \
  --owner="${GITHUB_USER}" \
  --repository=kube_local \
  --branch=main \
  --path=clusters/dev \
  --personal

echo "Bootstrap complete. Flux reconciles clusters/dev from Git."
