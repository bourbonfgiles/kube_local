# Local Kubernetes

A single k3d cluster (`dev`) on Linux/Docker that emulates a naked EKS cluster
closely enough to learn Flux, Cilium, Gateway API, cert-manager, external-dns
and Karpenter without cloud spend. Cluster shape lives in the dotfiles repo;
everything installed onto it lives here.

## What it achieves

- A cluster that boots with no CNI and no service routing, like a managed
  cluster before its add-ons — so the install order is explicit and realistic.
- Cilium as the entire network layer (CNI, kube-proxy replacement, L2
  load-balancing, Gateway API, Hubble) for eBPF and tracing study.
- GitOps from the first minute after bootstrap: Flux owns everything except the
  two things it cannot install itself.

## Cluster shape (dotfiles: `~/.config/k3d/config.yaml`)

| Decision | Why |
| --- | --- |
| 1 server + 3 agents | EKS hides the control plane; workloads only see the agents. |
| `--cluster-init` | Embedded etcd on the server, the datastore EKS uses, not SQLite. |
| Control-plane `NoSchedule` taint | Workloads land only on agents, as on EKS. |
| flannel, kube-proxy, servicelb, traefik, network-policy all disabled | Cilium provides all of it; nothing competes with it. |
| Region/zone/instance-type/nodegroup labels (`eu-west-2`, a/b/c, `m5.large`, `general`) | Topology-spread and affinity manifests behave as they would on EKS. |
| k3s minor pinned (currently 1.36) | A minor EKS also offers; match to target EKS, patch doesn't matter. |
| bpffs bind-mount on all nodes | Stable, inspectable eBPF maps for tracing. |

The cluster boots with every node `NotReady` by design.

## Networking: Cilium

- `kubeProxyReplacement: true` — kube-proxy is disabled, so Cilium implements
  Services in eBPF. Requires `k8sServiceHost: k3d-dev-serverlb` / port 6443
  because there is no kube-proxy to reach the API server through.
- `routingMode: tunnel` (vxlan) — k3d nodes are not L2-adjacent.
- LB-IPAM + L2 announcements — gives `type: LoadBalancer` services real IPs, the
  realistic way to expose TCP (e.g. a game server) instead of a NodePort.
- Gateway API enabled — the ingress direction post ingress-nginx EOL.
- Hubble (relay + UI) and `bpf.monitorAggregation: none` — full flow visibility
  and unaggregated trace events.

## Bootstrap

One imperative step (`bootstrap.sh`), because Flux is pods and pods need a CNI:

1. `helm install` Cilium using the values inlined in the Flux HelmRelease
   (extracted with `yq`), so Flux adopts the same release with no drift.
2. Apply the LB-IPAM pool.
3. `flux bootstrap github` — Flux reconciles this repo from here.

## Repo layout

```
bootstrap.sh                 Cilium + flux bootstrap (the only imperative step).
clusters/dev/                Flux entrypoint for this cluster.
infrastructure/cilium/       HelmRelease (inline values) + LB-IPAM.
kubernetes.md                This file.
```

- No `kustomization.yaml` anywhere: every component is a Helm chart via a
  HelmRelease, and Flux auto-includes plain manifests under the reconciled path.
- Cilium values are the single source of truth, inline in the HelmRelease.

## Registry

- Persistent standalone k3d registry (created by the dotfiles bootstrap, not the
  cluster) so the image cache survives cluster rebuilds.
- Push from the host at `localhost:5050`; nodes pull via the mirror at
  `k3d-registry.localhost:5000` (k3d prepends `k3d-` to the registry name).

## Deliberate EKS-fidelity gaps

Handled later via Flux, not emulated in the cluster itself:

- **IRSA / Pod Identity** — no AWS IAM locally; use static creds or the Pod
  Identity webhook when needed.
- **external-dns** — LocalStack Route53, so the provider config matches EKS.
- **Storage** — a local-path StorageClass aliased `gp3` with
  `WaitForFirstConsumer`; no real EBS.
- **Karpenter** — the KWOK provider; its AWS `EC2NodeClass` fields don't apply.

## Environment-specific values to verify

- LB-IPAM CIDR must sit inside the k3d Docker network (`docker network inspect
  k3d-dev`).
- `GITHUB_USER` and `GITHUB_TOKEN` exported before `flux bootstrap`.
