# 0004. Istio ambient beside Cilium; the edge stays on Cilium

**Status**: Proposed. Lesson 12 is a stub.

## Context

Lesson 4's HTTPS stops at the Gateway; traffic between pods is plain. From
lesson 11 the cluster runs a 20-service shop, and later lessons add more.
The options and what each touches are in [lesson 12](../12-istio-ambient.md).

## Decision

- Istio ambient for mTLS, workload identity and L7 policy. Namespaces opt in.
- Cilium WireGuard for whatever isn't meshed.
- The Cilium Gateway keeps the edge. Entry services such as `frontend-proxy`
  are `PERMISSIVE`; everything behind them is `STRICT`.

## Why

- Istio is what EKS shops mean by a mesh, and ambient is how new installs run
  it: no sidecar per pod, no restarts to inject.
- Keeping the edge leaves lessons 1 to 11 true, including cert-manager,
  ExternalDNS and Flagger on the Gateway.
- Opt-in namespaces keep BPF work (lesson 15) out of the mesh, so the book's
  tools see the app's own connections.

## Not chosen

| Option | Why not |
| --- | --- |
| Cilium mutual auth | Beta, and authenticates without encrypting |
| Linkerd | Stable releases come from Buoyant; open source is edge only |
| Istio sidecars | A proxy per pod; ambient replaces it for new installs |
| Istio's own Gateway at the edge | Moves cert-manager, ExternalDNS and every route. Kept as an exercise |

## Costs

- A second control plane, ztunnel on every node, and more memory.
- Cilium values for room: `socketLB.hostNamespaceOnly: true`,
  `cni.exclusive: false`. A Cilium restart, not a rebuild.
- Hubble loses L7 for meshed traffic; Istio's metrics replace it.
- The edge is a deliberate hole in strict mTLS.

## On EKS

The same. Nitro instances encrypt between each other in hardware, so
WireGuard is often dropped there and the mesh carries identity alone.
