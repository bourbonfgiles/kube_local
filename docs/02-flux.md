# 2. Flux

Make this repo the source of truth for the cluster.

EKS equivalent: the same. Flux is also an EKS add-on option.

## Before you start

- A fine-grained GitHub token on `kube_local`: Administration read/write (for
  the deploy key), Contents read/write, Metadata read.
- `flux` CLI from `fluxcd/tap` (dotfiles installs it).

## Tasks

1. `flux check --pre --context k3d-dev`.
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
   bootstrapping again.
3. `git pull`, then read `clusters/dev/flux-system/`: `gotk-components.yaml`
   is Flux itself, `gotk-sync.yaml` is the `GitRepository` and `Kustomization`
   that sync `clusters/dev`.
4. Decide a layout, e.g. `clusters/dev/infrastructure.yaml` and
   `clusters/dev/apps.yaml`: one Flux `Kustomization` each, pointing at
   `./infrastructure` and `./apps`, with `apps` `dependsOn` `infrastructure`.
5. Put the Gateway from lesson 1 under `infrastructure/`. Push, then
   `flux reconcile kustomization flux-system --with-source`.
6. A first app under `apps/`: podinfo as an `OCIRepository`
   (`oci://ghcr.io/stefanprodan/charts/podinfo`) and a `HelmRelease`, plus an
   `HTTPRoute` to it.
7. Drift: delete the route with `kubectl` and watch it come back. Delete the
   podinfo Deployment and notice it doesn't, until you set
   `spec.driftDetection.mode: enabled` on the HelmRelease.
8. Change `replicaCount` in Git and watch helm-controller roll it out.
9. Watch it all in k9s `:kustomizations`, `:helmreleases`, `:gitrepositories`.
   Then the CLI for what k9s can't: `flux trace` a pod, `flux suspend`/`flux
   resume` a HelmRelease, `flux diff kustomization`.
10. Adopt Cilium (below). Leave it until the rest feels routine.

## Adopting Cilium

A `HelmRelease` named `cilium` in `kube-system`, from `https://helm.cilium.io`,
same version as `bootstrap.sh`. Same name and namespace means Flux takes over
the existing release. Values: both files, base first, inline or as two
ConfigMaps under `valuesFrom` (it can't read files from Git). Before merging,
compare against `helm get values cilium -n kube-system`; they must match.

If it goes wrong: `flux suspend helmrelease cilium -n kube-system`, re-run
`overlays/local/bootstrap.sh`, fix the values, resume.

## Done when

- `flux get all -A` is all `Ready`.
- You can rebuild the cluster, run `bootstrap.sh` and the same bootstrap
  command, and everything comes back from Git.

| Argo CD | Flux |
| --- | --- |
| `Application` (Git path) | `GitRepository` + `Kustomization` (Flux's sync object; you never write Kustomize) |
| `Application` (Helm) | `HelmRepository` / `OCIRepository` + `HelmRelease` |
| App of apps | A `Kustomization` whose path holds more `Kustomization`s |
| Sync waves | `dependsOn` |
| Self-heal | Default for manifests; `driftDetection` for HelmReleases |

## Where it gets hard

- Flux reads GitHub, not your checkout. Push before expecting anything.
- CRD ordering: a `Kustomization` that applies objects whose CRDs come from a
  HelmRelease in the same sync fails until the CRDs exist. Split them and use
  `dependsOn`.
- Flux commits to the repo (bootstrap now, image automation later). `git pull`
  before you commit.
- Getting Cilium's values wrong takes the cluster network down, which also
  stops Flux from fixing it.

## Links

- <https://fluxcd.io/flux/installation/bootstrap/github/>
- <https://fluxcd.io/flux/components/kustomize/kustomizations/>
- <https://fluxcd.io/flux/components/helm/helmreleases/>
