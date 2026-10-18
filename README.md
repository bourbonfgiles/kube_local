# kube_local

Bootstraps a local cluster to the point where a GitOps tool can take over.

```
cilium/values.yaml            Cilium settings you'd also use on EKS.
external-dns/values.yaml      ExternalDNS sources and sync policy.
gateway/gateway.yaml          The shared Gateway every app routes through.
apps/
  online-boutique/            Microservices demo + its HTTPRoute (shop.kube.internal).
  minecraft/                  Java Minecraft server.
overlays/local/               Everything that only exists because this is k3d.
  bootstrap.sh                Installs Gateway API CRDs + Cilium. Nodes go Ready.
  cilium-values.yaml          k3d-only Cilium settings.
  lb-ipam.yaml                LoadBalancer IP pool on the k3d node network.
  dns/                        BIND for kube.internal, its TSIG key, CoreDNS forward.
  external-dns-values.yaml    RFC2136 provider pointed at that BIND.
  minecraft-values.yaml       NodePort 30000 (host port 25565).
```

Each component is a plain values file (or manifests), ready to become a Flux
`HelmRelease`. The install commands are in `kubernetes.md`.

## 1. Cluster (dotfiles)

```sh
cd ~/repos/personal/dotfiles
uv run python -c 'from dotfiles.services import k8s; k8s.create_cluster()'
```

Nodes start `NotReady`: there's no CNI yet.

## 2. Networking

```sh
./overlays/local/bootstrap.sh
```

Installs the Gateway API CRDs, then Cilium (Gateway API on), then the LB pool.

## 3. Flux (yours to do)

```sh
flux check --pre
export GITHUB_TOKEN=...   # fine-grained PAT on this repo: Administration + Contents read/write
flux bootstrap github --context k3d-dev \
  --owner bourbonfgiles --repository kube_local --personal --private=false \
  --branch master --path clusters/dev
```

That commits `clusters/dev/flux-system/` to the branch. Its `kustomization.yaml`
and `Kustomization` object are Flux's own plumbing; you don't need to write any
Kustomize yourself.

Then make Flux own Cilium: add a `HelmRepository` and a `HelmRelease` named
`cilium` in `kube-system` under `clusters/dev/`. Matching name and namespace
means helm-controller upgrades the release `bootstrap.sh` made instead of
installing a second one.

Flux pulls from GitHub, not this checkout: push before expecting a change.

To decide: a HelmRelease can't read `cilium/values.yaml` straight from Git
(`valuesFrom` takes ConfigMaps or Secrets). Either inline the values or turn the
two values files into ConfigMap manifests.

The full walkthrough, including a first HelmRelease behind the Gateway, is in
`kubernetes.md`.
