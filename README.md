# kube_local

Bootstrap for the local k3d `dev` cluster created by the dotfiles k3d config.

The cluster boots **CNI-less** (flannel and kube-proxy disabled), so nodes start
`NotReady`. That is deliberate: it mirrors a naked managed cluster where you own
everything above the control plane.

## Order

1. Create the cluster (from dotfiles): `k3d cluster create --config ~/.config/k3d/config.yaml`
2. Run the bootstrap: `./bootstrap.sh`
   - installs **Cilium** (nodes go Ready) — with kube-proxy replacement and
     Hubble enabled for BPF/tracing work
   - runs **`flux bootstrap`** — Flux takes over from Git
3. Everything else is declared in Git under `clusters/dev/` and reconciled by
   Flux. Nothing else is installed imperatively.

## Prerequisites

- `cilium` CLI, `flux` CLI, `kubectl` (all in the dotfiles brewfile)
- `GITHUB_USER` and `GITHUB_TOKEN` exported for `flux bootstrap`

## Why only two things here

Cilium and Flux are the chicken-and-egg: Flux is pods, pods need a CNI, so the
CNI cannot be installed *by* Flux. These two are the minimum imperative step;
GitOps owns the rest.
