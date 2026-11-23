# Decisions

One page per choice that shapes the cluster: what was picked, what it costs,
and what would change on EKS. The lessons hold the detail; these hold the why.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-flux.md) | Flux, not Argo CD | Accepted |
| [0002](0002-cilium.md) | Cilium as CNI and Gateway API implementation | Accepted |
| [0003](0003-sops.md) | SOPS for secrets in Git | Accepted |
| [0004](0004-istio-ambient.md) | Istio ambient beside Cilium; the edge stays on Cilium | Proposed |
| [0005](0005-kro.md) | kro for the platform layer, not Kratix and Backstage | Proposed |

Accepted means built; Proposed means its lesson isn't written yet.
