# 2. Flux

Make this repo the source of truth for the cluster: the Gateway from lesson 1,
then podinfo as a HelmRelease, then Cilium itself.

EKS equivalent: the same. On EKS you install Flux with `flux bootstrap` as
here; it isn't an EKS add-on.

## Before you start

On your machine:

- `flux`, `kubectl`, `helm`, `git`, `k9s`.
- A fine-grained GitHub token on `kube_local` with Administration read/write
  (for the deploy key), Contents read/write and Metadata read.

In the cluster: the platform, with nothing from lesson 1 left running.
`infrastructure/base/gateway/` from lesson 1 is still on disk.

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Flux components, GitRepository and Kustomization `flux-system` | | `clusters/dev/flux-system/` (bootstrap writes it) |
| Kustomizations `infra-base`, later `infra-local` | `flux-system` ns | `clusters/dev/infrastructure.yaml` |
| Kustomizations `apps-base`, `apps-local` | `flux-system` ns | `clusters/dev/apps.yaml` |
| Namespace, Gateway | `gateway/web` | `infrastructure/base/gateway/` |
| Namespace, OCIRepository, HelmRelease, ConfigMap `podinfo-values-base` | `podinfo` ns | `apps/base/podinfo/` |
| ConfigMap `podinfo-values-local`, HTTPRoute | `podinfo` ns | `apps/local/podinfo/` |
| HelmRepository, HelmRelease, ConfigMap `cilium-values-base` | `kube-system` ns | `infrastructure/base/cilium/` |
| ConfigMap `cilium-values-local` | `kube-system` ns | `infrastructure/local/cilium/` |

## Tasks

1. `flux --context k3d-dev check --pre`.
2. Bootstrap:
   ```sh
   export GITHUB_TOKEN=...
   flux bootstrap github --context k3d-dev \
     --owner bourbonfgiles --repository kube_local --personal --private=false \
     --branch master --path clusters/dev \
     --components-extra image-reflector-controller,image-automation-controller \
     --read-write-key
   ```
   The image controllers and write key are for lesson 8. Adding them later means
   deleting the deploy key Secret and bootstrapping again.
3. `git pull`: bootstrap committed `clusters/dev/flux-system/`.
   `gotk-components.yaml` is Flux itself; `gotk-sync.yaml` is the
   `GitRepository` and the `Kustomization` that apply everything under
   `clusters/dev/`.
4. The layers. Everything under `clusters/dev/` is applied by `flux-system`,
   so these files are how the rest of the repo gets in. Flux can't apply a
   path that doesn't exist in Git, so add each Kustomization when its path has
   its first file:
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
   `clusters/dev/apps.yaml` holds `apps-base` (`path: ./apps/base`,
   `dependsOn: [{name: infra-base}]`) and `apps-local` (`path: ./apps/local`,
   `dependsOn: [{name: apps-base}]`), separated by `---`. `infra-local`
   (`path: ./infrastructure/local`, `dependsOn: [{name: infra-base}]`) joins
   `infrastructure.yaml` when you adopt Cilium.
5. Commit `infrastructure/base/gateway/` and `clusters/dev/infrastructure.yaml`,
   push, then `flux --context k3d-dev reconcile kustomization flux-system --with-source`.
   k9s `:kustomizations -A`, then `:gateways -A`: the lesson 1 Gateway is
   back, from Git this time.
6. podinfo as a chart: the five files in the
   [layout example](README.md#helm-charts-and-their-values), plus
   `apps/base/podinfo/namespace.yaml` and a route:
   ```yaml
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
   The route is local because the hostname is. Push and
   `curl -H 'Host: podinfo.kube.internal' http://10.89.0.200/`.
7. Drift: `kubectl --context k3d-dev -n podinfo delete httproute podinfo`
   and watch `apps-local` put it back. Delete the podinfo Deployment and
   notice it doesn't come back, until you add
   `spec.driftDetection.mode: enabled` to `apps/base/podinfo/release.yaml`.
8. Change `replicaCount` in `apps/base/podinfo/values.yaml`, push, and watch
   helm-controller roll it out.
9. Watch it all in k9s `:kustomizations`, `:helmreleases`, `:gitrepositories`,
   `:ocirepositories`. Then the CLI for what k9s can't do:
   ```sh
   flux --context k3d-dev trace -n podinfo deployment podinfo
   flux --context k3d-dev diff kustomization apps-base --path ./apps/base
   ```
10. Adopt Cilium (below). Leave it until the rest feels routine.

## Adopting Cilium

`bootstrap.sh` installed Cilium with `helm`. A HelmRelease with the same
release name and namespace takes that release over:

| File | Contents |
| --- | --- |
| `clusters/dev/infrastructure.yaml` | Add Kustomization `infra-local` |
| `infrastructure/base/cilium/source.yaml` | HelmRepository `cilium` in `kube-system`, `url: https://helm.cilium.io` |
| `infrastructure/base/cilium/release.yaml` | HelmRelease `cilium` in `kube-system`, `chart.spec.version: 1.20.3`, `valuesFrom` the two ConfigMaps below, base first |
| `infrastructure/base/cilium/values.yaml` | ConfigMap `cilium-values-base`: the contents of `cilium/values.yaml` under `data.values.yaml` |
| `infrastructure/local/cilium/values.yaml` | ConfigMap `cilium-values-local`: the contents of `overlays/local/cilium-values.yaml` |

1. Compare what's installed with what you're about to commit:
   ```sh
   helm --kube-context k3d-dev get values cilium -n kube-system
   ```
   The two ConfigMaps merged must give exactly this.
2. Push. k9s `:helmreleases -n kube-system`: `cilium` upgrades in place, to
   the same values. `helm --kube-context k3d-dev history cilium -n kube-system`
   shows a new revision.
3. From now on the ConfigMaps are the truth. `bootstrap.sh` still installs
   Cilium from the two original files on a fresh cluster, before Flux exists;
   keep them identical to the ConfigMaps, or Flux changes Cilium on its first
   sync.

If it goes wrong:
`flux --context k3d-dev suspend helmrelease cilium -n kube-system`, re-run
`overlays/local/bootstrap.sh`, fix the values, then `flux --context k3d-dev resume helmrelease cilium -n kube-system`.

## Done when

- `flux --context k3d-dev get all -A` is all `Ready`.
- You can rebuild the cluster, run `bootstrap.sh` and the same bootstrap
  command, and everything comes back from Git.

## Where it gets hard

- Flux reads GitHub, not your checkout. Push before expecting anything.
- A HelmRelease in `base/` reports its local ConfigMap missing until
  `infra-local` (or `apps-local`) has applied it. It retries on its own.
- CRD ordering: a Flux Kustomization that applies an object whose CRD comes
  from a chart fails until that chart is installed. If anything a chart needs
  is in the same Kustomization, they wait on each other forever; later
  lessons give such objects their own Kustomization.
- Flux commits to the repo (bootstrap now, image automation later). `git pull`
  before you commit.
- Wrong Cilium values take the cluster network down, which also stops Flux
  from fixing it.

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

- <https://fluxcd.io/flux/installation/bootstrap/github/>
- <https://fluxcd.io/flux/components/kustomize/kustomizations/>
- <https://fluxcd.io/flux/components/helm/helmreleases/>
