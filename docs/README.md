# Learning path

Fourteen lessons on top of the platform, after a short one on the tools. Each one installs an upstream product,
first by hand so you can see what it does, then through Flux so Git owns it.
You write manifests and values, never application code.

## How a lesson is laid out

| Section | What's in it |
| --- | --- |
| **What it is** | The product: the problem it solves, how it works, the objects it adds. A diagram where it helps. |
| **On EKS** | What you'd run there instead, and what changes. |
| **Requirements** | What must already be in the cluster, and the tools you need on your machine. |
| **Install by hand** | `helm` and `kubectl apply -f` against files in `scratch/`. Small YAML files you edit and re-apply to see what each field does. Each check is a kubectl command, then a `sofka / k9s:` line with the keys. Cleaned up at the end. |
| **Install with Flux** | The same thing as files in the repo layout, committed and reconciled. |
| **Exercises** | Easy first, hardest last. |
| **Where it gets hard** | The failure modes, and how they show themselves. |

Lessons 1 and 2 are the exception: lesson 1 has no Flux yet, and lesson 2 is
Flux itself. Lesson 0 is a reference for the three tools you look with.

## Lessons

| # | Lesson | You end up with | Needs |
| --- | --- | --- | --- |
| 0 | [kubectl, sofka and k9s](00-tools.md) | Every check three ways; sofka's troubleshooting views | Platform |
| 1 | [Cilium and Gateway API](01-cilium.md) | A Gateway and routes, Hubble flows | Platform |
| 2 | [Flux](02-flux.md) | This repo syncing the cluster; podinfo from Git | 1 |
| 3 | [ExternalDNS](03-external-dns.md) | Routes get real `*.kube.internal` names | 2 |
| 4 | [cert-manager](04-cert-manager.md) | HTTPS on the Gateway, trusted by Zen | 3 |
| 5 | [SOPS](05-sops.md) | Secrets encrypted in Git | 2 |
| 6 | [Monitoring](06-monitoring.md) | Prometheus, Grafana, Cilium and Hubble metrics | 2, Cilium under Flux |
| 7 | [Registry](07-registry.md) | Images mirrored into the local ECR stand-in | 2 |
| 8 | [Image promotion](08-image-promotion.md) | Flux committing new tags to Git | 7 |
| 9 | [Flagger](09-flagger.md) | Automated canaries through the Gateway | 6, 7 |
| 10 | [OpenTelemetry Demo](10-otel-demo.md) | A 20-service shop with traces and Kafka | 3 |
| 11 | [KEDA](11-keda.md) | The shop's Kafka consumer scaled on lag | 10 |
| 12 | [Karpenter](12-karpenter.md) | Karpenter provisioning simulated nodes | 2, 7 |
| 13 | [Minecraft](13-minecraft.md) | A Java server you can join and profile with BPF | 2 |
| 14 | [Chaos Mesh](14-chaos.md) | Chaos experiments behind one on/off flag in Git | 10 |

## Where commands run

> [!IMPORTANT]
> Every command runs in a terminal on your machine, from the root of this repo
> (`~/repos/personal/kube_local`), unless its block starts with a comment such
> as `# in the pod shell`.

Every command names the cluster, so a work context can never be hit by
mistake:

| Tool | Flag |
| --- | --- |
| `kubectl`, `flux`, `cilium` | `--context k3d-dev` |
| `helm` | `--kube-context k3d-dev` |
| `sofka` | `sofka --context k3d-dev` |
| `k9s` | `k9s --context k3d-dev` |

`hubble` takes no context: it talks to the port-forward that
`cilium --context k3d-dev hubble port-forward` opens. `dig`, `curl`, `skopeo`,
`sops` and `mkcert` don't talk to the Kubernetes API at all.

A pod shell is `kubectl exec -it`, or `s` on the pod in sofka or k9s. Lesson
12 also works in a clone of the Karpenter repo; its blocks say so.

## Tools on your machine

These are binaries on your PATH, separate from anything in the cluster. Each
lesson lists the ones it needs.

| Tool | Lessons | Comes from |
| --- | --- | --- |
| `kubectl`, `helm`, `sofka`, `k9s` | All | dotfiles brewfile |
| `cilium`, `hubble` | 1, 6 | dotfiles brewfile |
| `flux` | 2 onwards | dotfiles brewfile (`fluxcd/tap`) |
| `git`, `curl`, `jq` | All | dotfiles brewfile |
| `dig` | 3 | Bazzite base image |
| `mkcert` | 4 | dotfiles brewfile |
| `/usr/bin/trust` | 4 | Bazzite base image (brew's `trust` is a different tool) |
| `sops`, `age`, `age-keygen` | 5 | dotfiles brewfile (`age-keygen` comes with `age`) |
| `skopeo` | 7, 8 | Bazzite base image |
| `go`, `ko`, `kwok`, `make` | 12 | dotfiles brewfile; `make` from the base image |
| `bpftrace`, BCC tools, `bpftool`, `perf` | 13 | dotfiles `bpf` step, then a reboot |
| Minecraft Java client | 13 | Not provided |

Check with `command -v <tool>`. If one's missing, run the dotfiles step that
provides it rather than installing it by hand.

## The two ways in

**By hand.** Files go in `scratch/<lesson>/`, which Git ignores. Charts go in
with `helm upgrade --install ... -f values.yaml`; everything else with
`kubectl --context k3d-dev apply -f <file>`. Edit, re-apply, watch what
changes. Each lesson ends this part by removing what it installed, so the
Flux part starts clean.

**Files.** Every YAML block starts with a comment naming its file. A change to
a file you already have shows the whole file again, with the new lines
between `# ── new ──` and `# ── end new ──`. Both are plain comments, so the
block still pastes as valid YAML.

**With Flux.** The same objects as files in the repo, in the layout lesson 2
sets up:

```
clusters/dev/            Flux's entry point: one Kustomization per layer
infrastructure/base/     Platform components, as you'd deploy them on EKS
infrastructure/local/    The k3d-only parts: local values, *.kube.internal routes
apps/base/, apps/local/  The same split for applications
```

A chart's values file becomes a ConfigMap that the HelmRelease reads.
[Lesson 2](02-flux.md#how-this-repo-is-laid-out) explains the layout and
that mapping.

## Working in sofka and k9s

Every object in these lessons has a view in both: `:` then the resource's
plural name (`:gateways`, `:httproutes`, `:helmreleases`, `:certificates`).
The lessons give the kubectl command first, then a `sofka / k9s:` line; the
keys are the same in both unless that line splits them. [Lesson 0](00-tools.md) has the full side by side, with kubectl.

| Does | sofka | k9s |
| --- | --- | --- |
| Describe. Status and events are where failures explain themselves. | `d` | `d` |
| Why it's unhealthy, with the evidence | `X` | |
| What changed while you watched | `T`, `:diff` | |
| Logs, previous container's logs | `l`, `p` | `l`, `p` |
| Shell in the container | `s` | `s` |
| Decode a Secret | `x` | `x` |
| Port-forward, for UIs such as Grafana | `f` or `Shift-f` | `Shift-f` |
| Only what's broken | `ctrl-z` | `ctrl-z` |
| Dependency tree | `:deploy -n <ns>`, then `:xray` | `:xray deploy <ns>` |
| Flux reconcile, suspend, resume | `t` | dotfiles plugins: `Shift-r`, `Shift-t` |
| Flux ownership chain | `:gitops` | `Shift-q` (plugin, runs `flux trace`) |

The `flux` CLI covers the rest: `flux diff`, `flux events`.

## Ground rules

- Once something is in Git, change it through Git. Flux reverts manual edits.
- Pin every chart and image version. `helm search repo <repo>/<chart>` or
  `helm show chart <oci url>` gives the latest.
- When something's stuck: `kubectl --context k3d-dev describe` it (`d`, or
  sofka's `X`), then
  `flux --context k3d-dev events -A`. The repo README's Troubleshooting table
  covers the platform.

## More lessons

Each is one or two charts and a clear thing to learn.

| Area | Idea |
| --- | --- |
| GitOps | **Flux notifications**: `Provider` and `Alert` objects posting reconcile failures to Discord or Slack. |
| GitOps | **Flux multi-tenancy**: a tenant namespace with its own service account, and a Flux `Kustomization` that can only touch it. |
| GitOps | **Cluster upgrade drill**: bump k3s a minor in the dotfiles config, rebuild, let Flux restore everything. Then a Cilium minor. |
| Security | **Tetragon**: Cilium's eBPF runtime security. Trace process execs and file access in pods. |
| Security | **Kyverno**: policies such as "images only from the local registry", in audit then enforce mode. |
| Security | **Trivy Operator**: vulnerability and config reports as CRDs you can browse in sofka or k9s. |
| Security | **Network policy hardening**: default-deny a namespace, then allow only what Hubble shows is needed. |
| AWS stand-ins | **MinIO** as S3, then **Velero** backing up namespaces to it and restoring into a rebuilt cluster. |
| AWS stand-ins | **CloudNativePG** as RDS: a Postgres cluster, failover, backups to MinIO. |
| Observability | **Loki and Alloy**: logs next to the metrics from lesson 6. |
| Resilience | **PodDisruptionBudgets and topology spread**: drain nodes and see what survives. The agents carry zone labels for this. |
| Resilience | **VPA with Goldilocks**: requests and limits recommended from real usage. |
