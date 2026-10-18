# Learning path

Lessons on top of the platform. Everything is an upstream Helm chart or a plain
manifest deployed by Flux; you write Flux objects and values, never
application code. Each lesson lists the objects it adds and the file each one
lives in, what it maps to on EKS, the tasks, how to tell you're done, and where
it gets hard.

| # | File | You end up with | Needs | Effort |
| --- | --- | --- | --- | --- |
| 1 | [01-cilium.md](01-cilium.md) | A Gateway and routes by hand, Hubble flows | Platform | Small |
| 2 | [02-flux.md](02-flux.md) | Flux syncing this repo; the Gateway and podinfo from Git | 1 | Medium |
| 3 | [03-external-dns.md](03-external-dns.md) | Routes get real `*.kube.internal` names | 2 | Medium |
| 4 | [04-cert-manager.md](04-cert-manager.md) | HTTPS on the Gateway, trusted by your browser | 2, 3 | Medium-large |
| 5 | [05-sops.md](05-sops.md) | Secrets encrypted in Git | 2 | Medium |
| 6 | [06-monitoring.md](06-monitoring.md) | Prometheus, Grafana, Cilium and Hubble metrics | 2, Cilium under Flux | Large |
| 7 | [07-registry.md](07-registry.md) | Upstream images mirrored into the local ECR stand-in | 2 | Small |
| 8 | [08-image-promotion.md](08-image-promotion.md) | Flux promoting mirrored tags and committing them to Git | 2, 7 | Medium-large |
| 9 | [09-flagger.md](09-flagger.md) | Automated canaries through the Gateway | 2, 6 | Large |
| 10 | [10-otel-demo.md](10-otel-demo.md) | A 20-service shop with traces, routes per service, Kafka | 2, 3 | Medium |
| 11 | [11-keda.md](11-keda.md) | The shop's Kafka consumer scaled on lag | 10 | Medium |
| 12 | [12-karpenter.md](12-karpenter.md) | Karpenter provisioning simulated nodes | 2, 7 | Large |
| 13 | [13-minecraft.md](13-minecraft.md) | A Java server you can join and profile with BPF | 2 | Small |
| 14 | [14-chaos.md](14-chaos.md) | Chaos Mesh experiments behind one on/off flag in Git | 2, 10 | Medium |

## Where commands run

Every command runs in a terminal on your machine, from the root of this repo
(`~/repos/personal/kube_local`). When one doesn't, its block starts with a
comment saying where: `# in the pod shell` (k9s `s` on the pod) or
`# in the karpenter clone`.

Every command names the cluster, so a work context can never be hit by
mistake:

| Tool | Flag |
| --- | --- |
| `kubectl`, `flux`, `cilium` | `--context k3d-dev` |
| `helm` | `--kube-context k3d-dev` |
| `k9s` | `k9s --context k3d-dev` |

`hubble` takes no context: it talks to the relay through
`cilium --context k3d-dev hubble port-forward`. `dig`, `curl` and `skopeo`
don't touch the Kubernetes API at all.

## Tools on your machine

These are the binaries on your PATH, separate from what's in the cluster. Each
lesson's "Before you start" lists the ones it needs under "On your machine".

| Tool | Used in | Comes from |
| --- | --- | --- |
| `kubectl`, `helm`, `flux`, `k9s`, `cilium`, `hubble` | All | dotfiles brewfile (`brew bundle`) |
| `git`, `curl`, `jq`, `go` | All, 12 | dotfiles brewfile |
| `dig`, `skopeo`, `make`, `/usr/bin/trust` | 3, 4, 7, 12 | Bazzite base image |
| `mkcert` | 4 | dotfiles brewfile |
| `sops`, `age`, `age-keygen` (comes with `age`) | 5 | dotfiles brewfile |
| `ko`, `kwok` | 12 | dotfiles brewfile |
| `bpftrace`, BCC tools (`/usr/share/bcc/tools/`), `bpftool`, `perf` | 13 | dotfiles `bpf` step, then a reboot |
| Minecraft Java client | 13 | Not provided |

Check one with `command -v <tool>`. If it's missing, run the dotfiles step
that provides it rather than installing it by hand.

## Where files go

Every object is YAML in this repo. You can apply any of it by hand first with
`kubectl --context k3d-dev apply -f <file>` to see what it does, then commit
it and let Flux apply the same file. Lesson 2 sets this layout up:

```
clusters/dev/
  flux-system/              Written by flux bootstrap. Don't edit.
  infrastructure.yaml       Flux Kustomizations infra-base, infra-local, infra-local-config
  apps.yaml                 Flux Kustomizations apps-base and apps-local
  secrets.yaml, chaos.yaml  Lessons 5 and 14
infrastructure/
  base/<component>/         What you'd deploy the same way on EKS
    namespace.yaml          Namespace
    source.yaml             HelmRepository or OCIRepository: where the chart comes from
    release.yaml            HelmRelease: chart, version, which values to use
    values.yaml             ConfigMap <component>-values-base
  local/<component>/        Only exists because this is k3d
    values.yaml             ConfigMap <component>-values-local
    route.yaml              HTTPRoute with a *.kube.internal hostname, and so on
  local-config/<component>/ Local objects whose CRDs come from a chart (ClusterIssuer, NodePool)
apps/
  base/<app>/               Same shape as infrastructure/
  local/<app>/
secrets/local/              SOPS-encrypted Secrets (lesson 5)
chaos/                      Chaos Mesh Schedules behind one switch (lesson 14)
```

`infra-base` is applied first and the other layers wait on it with
`dependsOn`; lesson 2 sets the order. An EKS cluster would get
its own `clusters/eks/` pointing at `infrastructure/base` and an
`infrastructure/eks/`. Nothing in `base/` changes.

A Flux `Kustomization` is Flux's sync object: "apply every manifest under this
path". It isn't Kustomize, and nothing here needs a `kustomization.yaml`.

### Plain manifests

The Gateway from lesson 1, by hand:

```sh
kubectl --context k3d-dev apply -f infrastructure/base/gateway/
```

With Flux: commit the same files and push. `infra-base` applies everything
under `infrastructure/base/`, and puts it back if you delete it.

```sh
git add infrastructure/base/gateway && git commit -m 'gateway' && git push
flux --context k3d-dev reconcile kustomization infra-base --with-source
```

### Helm charts and their values

Chart values are the keys in the chart's own `values.yaml`;
`helm show values <chart>` lists them. By hand you pass them as files, and a
later `-f` overrides an earlier one:

```sh
helm --kube-context k3d-dev install podinfo oci://ghcr.io/stefanprodan/charts/podinfo \
  --version 6.7.1 -n podinfo --create-namespace -f base.yaml -f local.yaml
```

Flux can't read a values file from Git, so each file's contents go into a
ConfigMap under the key `values.yaml`, and the HelmRelease lists them in the
same order as the `-f` flags:

```yaml
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
      name: podinfo-values-base      # like -f base.yaml
    - kind: ConfigMap
      name: podinfo-values-local     # like -f local.yaml, wins
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
```

- The ConfigMaps must be in the HelmRelease's namespace.
- The watch label makes Flux upgrade the release as soon as a ConfigMap
  changes, instead of at the next `interval`.
- `spec.values` on the HelmRelease overrides every ConfigMap. Use it only for
  values Flux itself rewrites, like an image tag in lesson 8; Flux can't edit
  inside a ConfigMap's string.
- A chart from a classic Helm repository uses a `HelmRepository` and
  `spec.chart.spec` instead of `chartRef`; lesson 3 shows it.

When a lesson says "base values" it means the contents of
`<layer>/base/<component>/values.yaml`; "local values" means
`<layer>/local/<component>/values.yaml`.

## Working in k9s

Every lesson's objects have a k9s view: type `:` and the resource's plural
name (`:helmreleases`, `:kustomizations`, `:gateways`, `:httproutes`,
`:certificates`, `:scaledobjects`, `:nodeclaims`). `d` describes (status and
events are where failures explain themselves), `l` logs, `s` a shell,
`x` decodes a Secret, `Shift-f` a port-forward for UIs like Grafana, and
`:xray deploy <ns>` a dependency tree. The dotfiles k9s Flux plugins add
reconcile, suspend and resume keys on Flux views; the hints at the top of the
screen list them. The `flux` CLI covers the rest: `flux trace`, `flux diff`,
`flux events`.

## Ground rules

- Once Flux is in, change things through Git. Flux reverts manual changes.
- Pin every chart and image version. `helm search repo <repo>/<chart>` or
  `helm show chart <oci url>` gives the latest.
- Base values are what you'd use on EKS; local values are what only k3d
  needs. `cilium/` and `overlays/local/` already split Cilium this way.
- When something's stuck, `flux --context k3d-dev get all -A`,
  `flux --context k3d-dev events -A`, and `d` on the object in k9s usually say
  why. The repo README's Troubleshooting table covers the platform.

## More lessons

Each is one or two charts and a clear thing to learn.

Platform and GitOps

- **Flux notifications**: `Provider` and `Alert` objects posting reconcile
  failures to Discord or Slack.
- **Flux multi-tenancy**: a tenant namespace with its own service account and
  a Flux `Kustomization` that can only touch it.
- **Headlamp or Capacitor**: a Flux-aware UI alongside k9s.
- **Cluster upgrade drill**: bump k3s a minor in the dotfiles config, rebuild,
  and let Flux restore everything. Then the same for a Cilium minor.

Security, with eBPF

- **Tetragon**: Cilium's eBPF runtime security. Trace process execs and file
  access in pods; pairs with the BPF Performance Tools book.
- **Kyverno**: policies such as "images only from the local registry" or
  "every Deployment has limits", in audit then enforce mode.
- **Trivy Operator**: vulnerability and config reports for everything running,
  as CRDs you can browse in k9s.
- **Network policy hardening**: default-deny a namespace, then allow only what
  Hubble shows is needed.

AWS stand-ins

- **MinIO** as S3, then **Velero** backing up namespaces to it and restoring
  into a rebuilt cluster.
- **CloudNativePG** as RDS: a Postgres cluster, failover, and backups to MinIO.
- **LocalStack** for SQS/SNS-style services, if its licence suits.

Observability and resilience

- **Loki and Alloy**: logs next to the metrics from lesson 6.
- **PodDisruptionBudgets and topology spread**: drain nodes with
  `kubectl --context k3d-dev drain` and see which workloads survive. The
  agents carry zone labels for this.
- **VPA with Goldilocks**: recommendations for requests and limits from real
  usage.
