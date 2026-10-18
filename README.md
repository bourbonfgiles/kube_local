# kube_local

Bootstraps a local cluster to the point where a GitOps tool can take over.

```
cilium/values.yaml            Cilium settings you'd also use on EKS.
overlays/local/               Everything that only exists because this is k3d.
  bootstrap.sh                Gateway API CRDs, Cilium, LB pool, local DNS.
  cilium-values.yaml          k3d-only Cilium settings.
  lb-ipam.yaml                LoadBalancer IP pool on the k3d node network.
  dns/                        BIND for kube.internal (stand-in for Route53).
```

## 1. Cluster (dotfiles)

```sh
cd ~/repos/personal/dotfiles
uv run python -c 'from dotfiles.services import k8s; k8s.create_cluster()'
```

Nodes start `NotReady`: there's no CNI yet.

## 2. Platform

```sh
./overlays/local/bootstrap.sh
```

Nodes go Ready, `type: LoadBalancer` gets `10.89.0.2xx` addresses, and
`kube.internal` resolves (empty until something writes to it). Nothing else is
installed.

## 3. Flux (yours to do)

Bootstrap command, what to build first, and the details ExternalDNS needs are in
`kubernetes.md`.
