#!/usr/bin/env bash
# Takes the CNI-less k3d cluster to ready: Cilium, LB pool, and BIND for kube.internal.
set -euo pipefail

CLUSTER="${1:-dev}"
CONTEXT="k3d-${CLUSTER}"
CILIUM_VERSION="1.20.3"
GATEWAY_API_VERSION="v1.6.3"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE}/../.."

# Cilium's operator only enables Gateway API if these CRDs exist when it starts.
CRDS="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard"
for crd in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
  kubectl --context "${CONTEXT}" apply --server-side -f "${CRDS}/gateway.networking.k8s.io_${crd}.yaml"
done

helm repo add cilium https://helm.cilium.io >/dev/null
helm repo update cilium >/dev/null

helm upgrade --install cilium cilium/cilium \
  --kube-context "${CONTEXT}" \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --values "${ROOT}/cilium/values.yaml" \
  --values "${HERE}/cilium-values.yaml" \
  --set k8sServiceHost="${CONTEXT}-serverlb"

cilium status --context "${CONTEXT}" --wait --wait-duration 10m
kubectl --context "${CONTEXT}" wait --for=condition=Ready nodes --all --timeout=5m
kubectl --context "${CONTEXT}" apply -f "${HERE}/lb-ipam.yaml"

"${HERE}/dns/tsig-secret.sh" "${CLUSTER}"
kubectl --context "${CONTEXT}" apply -f "${HERE}/dns/bind.yaml" -f "${HERE}/dns/coredns-custom.yaml"
