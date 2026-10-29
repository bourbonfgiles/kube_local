# 2. Flux

> You end up with: Flux syncing this repo, the lesson 1 Gateway and podinfo
> coming from Git, and, last, Cilium itself managed by Flux.

## What it is

Flux is a set of controllers that make the cluster match a Git repository.
You never run `kubectl apply` against the cluster; you push, and Flux pulls.
Each controller does one job and talks to the others through custom
resources:

| Controller | Watches | Does |
| --- | --- | --- |
| source-controller | `GitRepository`, `OCIRepository`, `HelmRepository` | Fetches a repo or chart on an interval and stores it as an artifact inside the cluster |
| kustomize-controller | `Kustomization` | Applies every manifest under a path in an artifact, deletes what was removed (`prune`), reports health |
| helm-controller | `HelmRelease` | Installs and upgrades a chart with given values, the way `helm upgrade --install` would |
| notification-controller | `Provider`, `Alert`, `Receiver` | Sends events out (Slack, Discord), takes webhooks in |
| image-reflector-controller | `ImageRepository`, `ImagePolicy` | Scans a registry's tags and picks one (lesson 8) |
| image-automation-controller | `ImageUpdateAutomation` | Commits the picked tag back to Git (lesson 8) |

```mermaid
flowchart LR
  gh["GitHub<br/>kube_local master"] -->|"pull every 1m"| src["source-controller<br/>GitRepository flux-system"]
  oci["ghcr.io chart"] -->|"pull"| src2["source-controller<br/>OCIRepository podinfo"]
  src -->|"artifact"| ks["kustomize-controller<br/>Kustomization per path"]
  ks -->|"apply, prune"| objs["Namespaces, Gateway,<br/>HelmReleases, ConfigMaps"]
  objs --> hc["helm-controller<br/>HelmRelease podinfo"]
  src2 -->|"chart"| hc
  hc -->|"install/upgrade"| rel["podinfo Deployment, Service"]
```

Everything runs on a loop: every `interval`, each object is reconciled again.
That's what makes drift correct itself.

> [!NOTE]
> A Flux `Kustomization` is Flux's sync object: "apply this path". It isn't
> Kustomize, and nothing in this repo needs a `kustomization.yaml`. Flux
> generates one internally when a path doesn't have one.

## On EKS

The same. You install Flux with `flux bootstrap` exactly as here; it isn't an
EKS add-on. The difference is credentials: on EKS the source and image
controllers would use IAM roles for ECR and KMS instead of tokens and keys.

## Requirements

**In the cluster**: the platform, with nothing left from lesson 1.

**On your machine**

| Tool | Why |
| --- | --- |
| `flux` | Install, bootstrap, and everything kubectl can't do |
| `kubectl`, `helm`, `git` | As usual |
| `sofka` or `k9s` | [Lesson 0](00-tools.md) |
| A GitHub fine-grained token | Only for bootstrap; [made just before it](#a-token-for-bootstrap) and not kept |

Check the cluster is ready for Flux:

```sh
flux --context k3d-dev check --pre
```

## Install by hand

First, Flux without Git: the controllers, and Flux objects you apply yourself.
This shows what each object does before bootstrap wires them to a repo.

### 1. The controllers

```sh
flux --context k3d-dev install
```

```sh
kubectl --context k3d-dev get pods -n flux-system
kubectl --context k3d-dev get crds | grep fluxcd
```

Four controllers, and the kinds they brought.

sofka / k9s: `:pods -n flux-system`, then `:crds` and `/fluxcd`

### 2. A chart, the Flux way

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    ui:
      message: hello from helm-controller
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
kubectl --context k3d-dev get ocirepositories,helmreleases -A
kubectl --context k3d-dev get pods -n podinfo
```

The OCIRepository fetches the chart, the HelmRelease installs it, and the pods
run it.

sofka / k9s: `:ocirepositories -A`, `:helmreleases -A`, `:pods -n podinfo`

### 3. Iterate

Edit `scratch/02/podinfo.yaml` in six steps, each building on the last. New
and changed lines sit between `# ── new ──` and `# ── end new ──`.

<details>
<summary>1. Change the message: a new Helm revision</summary>

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    ui:
      # ── new ──
      message: first change
      # ── end new ──
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
helm --kube-context k3d-dev history podinfo -n podinfo
```

Revision 2, made by helm-controller, not by you.

</details>

<details>
<summary>2. Three replicas</summary>

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    # ── new ──
    replicaCount: 3
    # ── end new ──
    ui:
      message: first change
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
kubectl --context k3d-dev get pods -n podinfo
```

Three pods.

</details>

<details>
<summary>3. Scale by hand: Flux doesn't notice</summary>

No file change.

```sh
kubectl --context k3d-dev -n podinfo scale deploy podinfo --replicas 1
kubectl --context k3d-dev get pods -n podinfo
```

It stays at 1: by default helm-controller only checks its own changes.

</details>

<details>
<summary>4. Drift detection: Flux puts it back</summary>

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  # ── new ──
  driftDetection:
    mode: enabled
  # ── end new ──
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    replicaCount: 3
    ui:
      message: first change
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
kubectl --context k3d-dev get pods -n podinfo
kubectl --context k3d-dev -n podinfo scale deploy podinfo --replicas 1
kubectl --context k3d-dev get pods -n podinfo -w
```

The apply alone brings it back to 3. Scale it down again and watch Flux undo it within the 5m interval. `ctrl-c` to stop watching.

</details>

<details>
<summary>5. Suspend, change, resume</summary>

```sh
flux --context k3d-dev suspend helmrelease podinfo -n flux-system
```

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  driftDetection:
    mode: enabled
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    replicaCount: 3
    ui:
      # ── new ──
      message: while suspended
      # ── end new ──
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
helm --kube-context k3d-dev history podinfo -n podinfo
```

No new revision: the HelmRelease changed, but helm-controller is paused. Resume it:

```sh
flux --context k3d-dev resume helmrelease podinfo -n flux-system
helm --kube-context k3d-dev history podinfo -n podinfo
```

A new revision appears within a few seconds of resuming.

</details>

<details>
<summary>6. A tag that doesn't exist, then back</summary>

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    # ── new ──
    tag: 9.9.9
    # ── end new ──
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  driftDetection:
    mode: enabled
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    replicaCount: 3
    ui:
      message: while suspended
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
```

```sh
kubectl --context k3d-dev -n flux-system describe ocirepository podinfo
flux --context k3d-dev get helmreleases -n flux-system
```

The OCIRepository reports the missing tag; the HelmRelease keeps running the last good chart. Put `6.7.1` back:

```yaml
# scratch/02/podinfo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    # ── new ──
    tag: 6.7.1
    # ── end new ──
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  releaseName: podinfo
  targetNamespace: podinfo
  install:
    createNamespace: true
  driftDetection:
    mode: enabled
  chartRef:
    kind: OCIRepository
    name: podinfo
  values:
    replicaCount: 3
    ui:
      message: while suspended
```

```sh
kubectl --context k3d-dev apply -f scratch/02/podinfo.yaml
flux --context k3d-dev reconcile source oci podinfo -n flux-system
kubectl --context k3d-dev -n flux-system get ocirepository podinfo
```

`READY True` again.

</details>

sofka / k9s: `d` on the OCIRepository for its error. They differ on Helm and
Flux actions:

- sofka: `⏎` on the HelmRelease for Helm's revisions; `t` to suspend or
  reconcile.
- k9s: `:helm`, `r` on `podinfo`; `Shift-t` to suspend, `Shift-r` to
  reconcile (dotfiles plugins).

> [!TIP]
> A sofka extra ([lesson 0](00-tools.md)): with `ref.tag: 9.9.9`, `ctrl-z` on
> `:ocirepositories -A` leaves only the broken source, and `X` gives its
> `Ready` reason. `:gitops` on the podinfo Deployment walks up to the
> HelmRelease and its source, with the applied and latest revisions side by
> side.

### 4. Clean up

```sh
kubectl --context k3d-dev delete -f scratch/02/podinfo.yaml   # helm-controller uninstalls podinfo
kubectl --context k3d-dev delete namespace podinfo
flux --context k3d-dev uninstall
```

Delete the HelmRelease before uninstalling Flux. Otherwise nothing is left to
uninstall the chart.

## Install with Flux

Bootstrap installs the controllers again, but this time commits them to this
repo and points them at it, so Flux manages itself from Git.

### A token for bootstrap

Bootstrap uses a GitHub token once: to add a deploy key to the repo and push
its first commit. From then on Flux uses the deploy key, which it keeps in
Secret `flux-system/flux-system`. The token isn't stored anywhere, so make a
short-lived one now and let it expire.

On GitHub: **Settings → Developer settings → Personal access tokens →
Fine-grained tokens → Generate new token**.

| Field | Value |
| --- | --- |
| Token name | `flux-bootstrap-k3d-dev` |
| Expiration | 7 days |
| Resource owner | `bourbonfgiles` |
| Repository access | Only select repositories: `kube_local` |
| Administration | Read and write: creates the deploy key |
| Contents | Read and write: pushes `clusters/dev/flux-system/` |
| Metadata | Read-only (GitHub adds it) |

Copy the token. Read it into the shell without echoing it or leaving it in
your history:

```sh
read -rs 'GITHUB_TOKEN?GitHub token: ' && export GITHUB_TOKEN
```

You need a new one only if you bootstrap again, for example on a new cluster.

### Bootstrap

```sh
flux bootstrap github --context k3d-dev \
  --owner bourbonfgiles --repository kube_local --personal --private=false \
  --branch master --path clusters/dev \
  --components-extra image-reflector-controller,image-automation-controller \
  --read-write-key
```

| Flag | Why |
| --- | --- |
| `--path clusters/dev` | Flux applies everything under this folder. It's the entry point. |
| `--components-extra ...` | The image controllers for lesson 8. Adding them later means bootstrapping again. |
| `--read-write-key` | The deploy key can push, also for lesson 8. A read-only key isn't upgraded in place. |

Then drop the token and fetch bootstrap's commit (in the repo root):

```sh
unset GITHUB_TOKEN
git pull
kubectl --context k3d-dev -n flux-system get secret flux-system
```

The Secret is the deploy key; the same key shows under the repo's
**Settings → Deploy keys**. Bootstrap committed `clusters/dev/flux-system/`:

- `gotk-components.yaml`: Flux itself.
- `gotk-sync.yaml`: a `GitRepository` for this repo and a `Kustomization`
  named `flux-system` that applies `./clusters/dev`.

## How this repo is laid out

Once Flux is in, everything you add goes in one of these places:

```
clusters/dev/
  flux-system/                 Written by bootstrap. Don't edit.
  infrastructure.yaml          Kustomizations infra-base, infra-local (and later infra-local-config)
  apps.yaml                    Kustomizations apps-base, apps-local
infrastructure/
  base/<component>/            As you'd deploy it on EKS
    namespace.yaml
    source.yaml                HelmRepository or OCIRepository
    release.yaml               HelmRelease
    values.yaml                ConfigMap <component>-values-base
  local/<component>/           Only because this is k3d
    values.yaml                ConfigMap <component>-values-local
    route.yaml                 Anything naming *.kube.internal
  local-config/<component>/    Local objects whose CRDs come from a chart (lesson 4)
apps/
  base/<app>/, local/<app>/    The same split for applications
```

An EKS cluster would get `clusters/eks/` pointing at the same `base/`
folders plus an `infrastructure/eks/`. Nothing in `base/` changes.

### Layers

`flux-system` applies `clusters/dev/`, which holds one Kustomization per
layer. Each points at a folder and can wait for another with `dependsOn`:

```mermaid
flowchart LR
  fs["flux-system<br/>./clusters/dev"] --> ib["infra-base<br/>./infrastructure/base"]
  ib --> il["infra-local<br/>./infrastructure/local"]
  ib --> ab["apps-base<br/>./apps/base"]
  ab --> al["apps-local<br/>./apps/local"]
```

```yaml
# clusters/dev/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-base
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/base
  prune: true
```

The others are the same shape with their own `name`, `path` and `dependsOn`
(`apps-base` waits on `infra-base`; `apps-local` on `apps-base`; `infra-local`
on `infra-base`). Add each one when its folder has its first file: Flux can't
apply a path that isn't in Git.

### Chart values

By hand, values are files and a later `-f` wins:

```sh
helm upgrade --install podinfo ... -f values-base.yaml -f values-local.yaml
```

Flux can't read a values file from Git, so each file's contents go into a
ConfigMap under the key `values.yaml`, and the HelmRelease lists them in the
same order:

| By hand | With Flux |
| --- | --- |
| `-f values-base.yaml` | ConfigMap `podinfo-values-base` in `apps/base/podinfo/values.yaml` |
| `-f values-local.yaml` | ConfigMap `podinfo-values-local` in `apps/local/podinfo/values.yaml` |
| `--set image.tag=...` | `spec.values` on the HelmRelease. Overrides every ConfigMap. |

<details>
<summary>podinfo as Flux files</summary>

```yaml
# apps/base/podinfo/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: podinfo
---
# apps/base/podinfo/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: podinfo
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    tag: 6.7.1
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
---
# apps/base/podinfo/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: podinfo
spec:
  interval: 10m
  chartRef:
    kind: OCIRepository
    name: podinfo
  valuesFrom:
    - kind: ConfigMap
      name: podinfo-values-base
    - kind: ConfigMap
      name: podinfo-values-local
---
# apps/base/podinfo/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: podinfo-values-base
  namespace: podinfo
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    replicaCount: 2
---
# apps/local/podinfo/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: podinfo-values-local
  namespace: podinfo
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    ui:
      message: k3d
---
# apps/local/podinfo/route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: podinfo
  namespace: podinfo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames: [podinfo.kube.internal]
  rules:
    - backendRefs:
        - name: podinfo
          port: 9898
```

</details>

- The ConfigMaps must be in the HelmRelease's namespace.
- The watch label makes Flux upgrade as soon as a ConfigMap changes, instead
  of at the next `interval`.
- The route is local because its hostname is.

### First objects from Git

1. `mkdir -p infrastructure/base/gateway` and move the Gateway in:
   `cp scratch/01/gateway.yaml infrastructure/base/gateway/`.
2. Write `clusters/dev/infrastructure.yaml` with `infra-base`.
3. Commit, push, and reconcile rather than waiting a minute:
   ```sh
   flux --context k3d-dev reconcile kustomization flux-system --with-source
   ```
4. `kubectl --context k3d-dev get kustomizations,gateways -A`: the Gateway is
   back, from Git. sofka / k9s: `:kustomizations -A`, then `:gateways -A`.
5. The podinfo files above, plus the apps layers:
   ```yaml
   # clusters/dev/apps.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: apps-base
     namespace: flux-system
   spec:
     interval: 10m
     retryInterval: 1m
     dependsOn:
       - name: infra-base
     sourceRef:
       kind: GitRepository
       name: flux-system
     path: ./apps/base
     prune: true
   ---
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: apps-local
     namespace: flux-system
   spec:
     interval: 10m
     retryInterval: 1m
     dependsOn:
       - name: apps-base
     sourceRef:
       kind: GitRepository
       name: flux-system
     path: ./apps/local
     prune: true
   ```
   Push, then
   `curl -s -H 'Host: podinfo.kube.internal' http://10.89.0.200/ | jq .message`.

## Exercises

1. Drift on a plain manifest: delete the route with `kubectl` and watch
   `apps-local` put it back within its interval.
2. Drift on a chart: delete the podinfo Deployment. It doesn't come back until
   you add `spec.driftDetection.mode: enabled` to the HelmRelease.
3. Change `replicaCount` in `apps/base/podinfo/values.yaml` and push. Watch it upgrade:
   `kubectl --context k3d-dev get helmreleases -A -w`.
4. Ask Flux where a pod came from:
   ```sh
   flux --context k3d-dev trace -n podinfo deployment podinfo
   ```
   The same from a TUI: sofka `:gitops` on the Deployment; k9s `Shift-q` on
   it (dotfiles plugin).
5. Preview a change before pushing:
   ```sh
   flux --context k3d-dev diff kustomization apps-base --path ./apps/base
   ```
6. Harder: adopt Cilium, below.

## Adopting Cilium

`bootstrap.sh` installed Cilium with `helm`. A HelmRelease with the same
release name and namespace takes that release over, so Flux owns the CNI.

| File | Contents |
| --- | --- |
| `clusters/dev/infrastructure.yaml` | Add Kustomization `infra-local` |
| `infrastructure/base/cilium/source.yaml` | HelmRepository `cilium` in `kube-system`, `url: https://helm.cilium.io` |
| `infrastructure/base/cilium/release.yaml` | HelmRelease `cilium` in `kube-system`, `chart.spec.version: 1.20.3`, `valuesFrom` both ConfigMaps, base first |
| `infrastructure/base/cilium/values.yaml` | ConfigMap `cilium-values-base`: the contents of `cilium/values.yaml` |
| `infrastructure/local/cilium/values.yaml` | ConfigMap `cilium-values-local`: the contents of `overlays/local/cilium-values.yaml` |

<details>
<summary>Cilium as Flux files</summary>

```yaml
# clusters/dev/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-base
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/base
  prune: true
# ── new ──
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-local
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  dependsOn:
    - name: infra-base
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/local
  prune: true
# ── end new ──
```

```yaml
# infrastructure/base/cilium/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 1h
  url: https://helm.cilium.io
---
# infrastructure/base/cilium/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 10m
  chart:
    spec:
      chart: cilium
      version: 1.20.3
      sourceRef:
        kind: HelmRepository
        name: cilium
  valuesFrom:
    - kind: ConfigMap
      name: cilium-values-base
    - kind: ConfigMap
      name: cilium-values-local
---
# infrastructure/base/cilium/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-values-base
  namespace: kube-system
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    kubeProxyReplacement: true

    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true

    bpf:
      monitorAggregation: none

    gatewayAPI:
      enabled: true
---
# infrastructure/local/cilium/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-values-local
  namespace: kube-system
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    # kube-proxy is disabled, so Cilium needs the API server address directly.
    k8sServiceHost: k3d-dev-serverlb
    k8sServicePort: 6443

    # Native routing would need pod CIDR routes on every node; k3d doesn't add them.
    routingMode: tunnel
    tunnelProtocol: vxlan

    # Stands in for a cloud load balancer. Inert until lb-ipam.yaml is applied.
    l2announcements:
      enabled: true

    # k3d nodes don't propagate mounts, so an auto-mounted cgroup2 never reaches the
    # agent and socket-LB hooks miss every pod. Use the node's own cgroup root.
    cgroup:
      autoMount:
        enabled: false
      hostRoot: /sys/fs/cgroup

    operator:
      replicas: 1

    # Use the pod CIDR k3s assigns each node (10.42.0.0/16). Cilium's own default
    # pool, 10.0.0.0/8, overlaps the node network.
    ipam:
      mode: kubernetes
```

The ConfigMaps hold `cilium/values.yaml` and
`overlays/local/cilium-values.yaml` unchanged.

</details>

1. Compare what's installed with what you're about to commit. The two
   ConfigMaps merged must give exactly this:
   ```sh
   helm --kube-context k3d-dev get values cilium -n kube-system
   ```
2. Push. `kubectl --context k3d-dev get helmreleases -n kube-system -w`:
   `cilium` upgrades to the same values,
   and `helm --kube-context k3d-dev history cilium -n kube-system` shows a new
   revision.
3. From now on the ConfigMaps are the truth. `bootstrap.sh` still installs
   Cilium from the original two files on a fresh cluster, before Flux exists,
   so keep them identical.

> [!WARNING]
> Wrong Cilium values take the cluster network down, and with it Flux's
> ability to fix them. If it goes wrong, from the repo root:
>
> ```sh
> flux --context k3d-dev suspend helmrelease cilium -n kube-system
> ./overlays/local/bootstrap.sh
> ```
>
> Fix the values in Git and push, then hand Cilium back to Flux:
>
> ```sh
> flux --context k3d-dev resume helmrelease cilium -n kube-system
> kubectl --context k3d-dev get helmreleases -n kube-system -w
> ```

## Where it gets hard

- Flux reads GitHub, not your checkout. Push before expecting anything.
- A HelmRelease in `base/` reports its local ConfigMap missing until the local
  layer has applied it. It retries on its own.
- CRD ordering: a Kustomization that applies an object whose CRD comes from a
  chart fails until the chart is installed. If something the chart needs is in
  the same Kustomization, they wait on each other forever. Lesson 4 gives such
  objects their own layer.
- Flux commits to the repo (bootstrap now, image automation in lesson 8).
  `git pull` before you commit.

## Coming from Argo CD

| Argo CD | Flux |
| --- | --- |
| `Application` (Git path) | `GitRepository` + `Kustomization` |
| `Application` (Helm) | `HelmRepository` / `OCIRepository` + `HelmRelease` |
| App of apps | A `Kustomization` whose path holds more `Kustomization`s, as `clusters/dev/` does |
| Sync waves | `dependsOn` |
| Self-heal | Default for manifests; `driftDetection` for HelmReleases |
| Argo Rollouts | Flagger (lesson 9) |
| Argo CD Image Updater | Image automation controllers (lesson 8) |

## Links

- <https://fluxcd.io/flux/components/>
- <https://fluxcd.io/flux/installation/bootstrap/github/>
- <https://fluxcd.io/flux/components/kustomize/kustomizations/>
- <https://fluxcd.io/flux/components/helm/helmreleases/>
