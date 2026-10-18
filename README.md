# kube_local

GitOps for the local k3d `dev` cluster created by the dotfiles k3d config.

The cluster boots **CNI-less** (flannel and kube-proxy disabled), so nodes start
`NotReady` — the same clean slate a managed cluster gives you before add-ons.

## Layout

```
bootstrap.sh            One-time imperative step: Cilium + flux bootstrap.
clusters/dev/           Flux entrypoint for this cluster.
infrastructure/
  cilium/               CNI: HelmRelease (inline values) + LB-IPAM.
```

No `kustomization.yaml` files: everything is a Helm chart via a HelmRelease,
and Flux auto-includes the plain manifests under the path it reconciles.

## Order

1. Create the cluster (dotfiles): `k3d cluster create --config ~/.config/k3d/config.yaml`
2. Export `GITHUB_USER` and `GITHUB_TOKEN`, then `./bootstrap.sh`:
   - helm-installs **Cilium** with the HelmRelease's inline values (nodes go Ready)
   - runs **`flux bootstrap`**, which adopts Cilium and reconciles the rest
3. Add components as HelmReleases under `infrastructure/` and `apps/`; Flux applies them.

## Why Cilium is installed twice (helm then Flux)

Flux is pods and pods need a CNI, so Cilium cannot be installed by Flux. The
bootstrap helm-installs it using the **same inline values** the Flux HelmRelease
declares (extracted with `yq`), so Flux adopts the existing release rather than
fighting it. The HelmRelease is the single source of truth for the values.

## Cilium notes

- `kubeProxyReplacement: true` and `k8sServiceHost: k3d-dev-serverlb` are
  required: kube-proxy is disabled, so Cilium needs the API server address.
- LB-IPAM + L2 announcements give `type: LoadBalancer` services real IPs, the
  realistic way to expose TCP (e.g. a Minecraft service) rather than a NodePort.
