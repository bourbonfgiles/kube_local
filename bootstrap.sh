#!/usr/bin/env bash
# Bootstrap a freshly created k3d "dev" cluster.
#
# The cluster is created CNI-less on purpose (flannel and kube-proxy are
# disabled in the k3d config), so it comes up with every node NotReady. This
# script installs the two things that must exist before GitOps can take over:
#
#   1. Cilium  - the CNI. Nodes go Ready once it is running.
#   2. Flux    - reconciles this repo from here on.
#
# Everything else (cert-manager, external-dns, apps, ...) is NOT here; it lives
# in Git and is installed by Flux. This script is the only imperative step,
# mirroring how a managed cluster hands you a control plane + CNI add-on and
# you declare the rest.
set -euo pipefail

CLUSTER="dev"

# --- 1. Cilium ---------------------------------------------------------------
# kube-proxy is disabled, so Cilium must replace it AND be told how to reach the
# API server directly (there is no kube-proxy to route through). On k3d the API
# server is reachable at the server load balancer inside the Docker network.
K8S_SERVICE_HOST="k3d-${CLUSTER}-server-0"
K8S_SERVICE_PORT="6443"

cilium install \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${K8S_SERVICE_HOST}" \
  --set k8sServicePort="${K8S_SERVICE_PORT}" \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set bpf.monitorAggregation=none \
  --set debug.enabled=true

cilium status --wait

# --- 2. Flux -----------------------------------------------------------------
# Needs a GitHub token in GITHUB_TOKEN (and GITHUB_USER). flux bootstrap writes
# its own manifests into this repo under clusters/dev/ and starts reconciling.
flux bootstrap github \
  --owner="${GITHUB_USER}" \
  --repository=kube_local \
  --branch=main \
  --path=clusters/dev \
  --personal

echo "Bootstrap complete. Flux now reconciles clusters/dev from Git."
