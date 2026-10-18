# kube_local

Bootstraps a local cluster to the point where a GitOps tool can take over.

```
cilium/values.yaml          Cilium settings you'd also use on EKS.
overlays/local/             Everything that only exists because this is k3d.
  bootstrap.sh              Installs Cilium (base + local values). Nodes go Ready.
  cilium-values.yaml        k3d-only Cilium settings.
  lb-ipam.yaml              LoadBalancer IP pool on the k3d node network.
```

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
