# Learning path

Sixteen lessons on top of the platform, after a short one on the tools, and
four more planned. Each one installs an upstream product through Flux, and
every change after that is a commit. The `helm` / `kubectl apply` equivalent
is shown once, for comparison, never run. You write manifests and values,
never application code.

## How a lesson is laid out

| Section | What's in it |
| --- | --- |
| **What it is** | The product: the problem it solves, how it works, the objects it adds. A diagram where it helps. |
| **On EKS** | What you'd run there instead, and what changes. |
| **Requirements** | What must already be in the cluster, and the tools you need on your machine. |
| **By hand, for comparison** | The `helm` / `kubectl apply` it replaces, marked **Example only**. Read, don't run. |
| **Install with Flux** | A kind / name / file table, then the files, committed and reconciled. Each check is a kubectl command, then a `sofka / k9s:` line with the keys. |
| **Iterate** | A table of changes worth knowing: the field, the file, what happens. Each is one commit if you want to try it. Full steps only where something surprises or a later lesson needs it. |
| **Exercises** | Only the ones worth doing, easy first, hardest last. |
| **Where it gets hard** | The failure modes, and how they show themselves. |

The lessons build one cluster in order: each assumes every lesson before it
is done, and nothing is optional. The **Uses** column below says which
earlier lessons it leans on most.

Lesson 1 is the exception: Cilium is the CNI, so it and the first Gateway
come before Flux, by hand. Lesson 2 is Flux itself. Lesson 0 is a reference for the three tools you look with.

## Lessons

| # | Lesson | You end up with | Uses |
| --- | --- | --- | --- |
| 0 | [kubectl, sofka and k9s](00-tools.md) | Every check three ways; sofka's troubleshooting views | Platform |
| 1 | [Cilium and Gateway API](01-cilium.md) | A Gateway and routes, Hubble flows | Platform |
| 2 | [Flux](02-flux.md) | This repo syncing the cluster; Cilium and podinfo from Git | 1 |
| 3 | [ExternalDNS](03-external-dns.md) | Routes get real `*.kube.internal` names | 2 |
| 4 | [cert-manager](04-cert-manager.md) | HTTPS on the Gateway, trusted by Zen | 3 |
| 5 | [SOPS](05-sops.md) | Secrets encrypted in Git | 2 |
| 6 | [Flux Operator](06-flux-operator.md) | Flux run by Flux Operator; the Flux Web UI at `flux.kube.internal`; failures posted to Discord | 2, 3, 4, 5 |
| 7 | [Monitoring](07-monitoring.md) | Prometheus, Grafana, Cilium and Hubble metrics | 2 |
| 8 | [Registry](08-registry.md) | Images mirrored into the local ECR stand-in | 2 |
| 9 | [Image promotion](09-image-promotion.md) | Flux committing new tags to Git | 8 |
| 10 | [Flagger](10-flagger.md) | Automated canaries through the Gateway; podinfo retired | 7, 9 |
| 11 | [OpenTelemetry Demo](11-otel-demo.md) | A 20-service shop with traces and Kafka | 3 |
| 12 | [Istio ambient](12-istio-ambient.md) (stub) | mTLS and identity between the shop's services; WireGuard for the rest | 1, 7, 10, 11 |
| 13 | [KEDA](13-keda.md) | The shop's Kafka consumer scaled on lag | 11 |
| 14 | [Karpenter](14-karpenter.md) | Karpenter provisioning simulated nodes | 2, 8 |
| 15 | [Minecraft](15-minecraft.md) | A Java server you can join and profile with BPF | 2 |
| 16 | [Chaos Mesh](16-chaos.md) | Chaos experiments behind one on/off flag in Git | 11 |

## Where commands run

> [!IMPORTANT]
> Every command runs in a terminal on your machine, unless its block starts
> with a comment such as `# in the pod shell`. Every path is written in full,
> so it doesn't matter where you are. Git commands use
> `git -C ~/repos/personal/kube_local`.

Everything lives side by side in `~/repos/personal`:

| Folder | What |
| --- | --- |
| `~/repos/personal/dotfiles` | The machine and the CNI-less cluster |
| `~/repos/personal/kube_local` | This repo: the platform, the lessons, and everything Flux applies |
| `~/repos/personal/scratch` | Not a repo. Lessons 0 and 1 and the odd local check |
| `~/repos/personal/karpenter`, `~/repos/personal/FlameGraph` | Clones for lessons 14 and 15 |

Every command names the cluster, so a work context can never be hit by
mistake:

| Tool | Flag |
| --- | --- |
| `kubectl`, `flux`, `cilium` | `--context k3d-dev` |
| `helm` | `--kube-context k3d-dev` |
| `sofka`, `k9s` | Launched bare; `:ctx`, then `k3d-dev`, inside the app |

`hubble` takes no context: it talks to the port-forward that
`cilium --context k3d-dev hubble port-forward` opens. `dig`, `curl`, `skopeo`,
`sops` and `mkcert` don't talk to the Kubernetes API at all.

A pod shell is `kubectl exec -it`, or `s` on the pod in sofka or k9s.

## Tools on your machine

These are binaries on your PATH, separate from anything in the cluster. Each
lesson lists the ones it needs.

| Tool | Lessons | Comes from |
| --- | --- | --- |
| `kubectl`, `helm`, `sofka`, `k9s` | All | dotfiles brewfile |
| `cilium`, `hubble` | 1, 6, 7 | dotfiles brewfile |
| `flux` | 2 onwards | dotfiles brewfile (`fluxcd/tap`) |
| `git`, `curl`, `jq` | All | dotfiles brewfile |
| `dig` | 3 | Bazzite base image |
| `mkcert` | 4 | dotfiles brewfile |
| `/usr/bin/trust` | 4 | Bazzite base image (brew's `trust` is a different tool) |
| `sops`, `age`, `age-keygen` | 5 | dotfiles brewfile (`age-keygen` comes with `age`) |
| `skopeo` | 8, 9 | Bazzite base image |
| `go`, `ko`, `kwok`, `make` | 13 | dotfiles brewfile; `make` from the base image |
| `bpftrace`, BCC tools, `bpftool`, `perf` | 14 | os_build image |
| Minecraft Java client | 14 | Not provided |

Check with `command -v <tool>`. If one's missing, add it to the dotfiles brewfile
and run `chezmoi apply` rather than installing it by hand.

## How you work

**Through Git.** From lesson 2 on, nothing is applied by hand except
Secrets until lesson 5 and builds or registry pushes. You write a file, commit,
push, and `flux reconcile` rather than wait. `~/repos/personal/scratch` is only
for lessons 0 and 1 and the odd local check.

**Files.** Every file block is titled **Write `path`** (new) or **Replace
`path`**. A Replace has two whole-file blocks: **Before**, what the file holds
now, and **After**, what to paste over it, with new or changed lines between
`# ── new ──` and `# ── end new ──`. Both markers are plain comments, so the
block still pastes as valid YAML. Anything else is labelled **Example only**.

**What stays.** podinfo is the example app for lessons 2 to 10, retired at the
end of lesson 10. Everything else you install is kept.

**With Flux.** The same objects as files in the repo, in the layout lesson 2
sets up:

**Example only: the layout**
```
~/repos/personal/kube_local/
  clusters/dev/              Flux's entry point: only Kustomizations, one per layer
  infrastructure/base/       What every cluster gets, routes included; the domain is ${CLUSTER_DOMAIN}
  infrastructure/dev/        Only what differs on this cluster: its values, its own objects
  infrastructure/dev-config/ This cluster's objects whose CRDs come from a chart
  apps/base/, apps/dev/      The same split for applications
```

A chart's values file becomes a ConfigMap that the HelmRelease reads.
[Lesson 2](02-flux.md#how-this-repo-is-laid-out) explains the layout and
that mapping.

## Working in sofka and k9s

Every object in these lessons has a view in both: `:` then the resource's
plural name (`:gateways`, `:httproutes`, `:helmreleases`, `:certificates`),
then the namespace as a word: `:pods podinfo`, or `:pods all`. No `-n` or `-A`
inside the apps.
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
| Dependency tree | `:deploy podinfo`, then `:xray` | `:xray deploy podinfo` |
| Flux reconcile, suspend, resume | `t` | dotfiles plugins: `Shift-r`, `Shift-t` |
| Flux ownership chain | `:gitops` on the highlighted object | `Shift-q` (plugin, runs `flux trace`) |

The `flux` CLI covers the rest: `flux diff`, `flux events`.

## Ground rules

- Once something is in Git, change it through Git. Flux reverts manual edits.
- Pin every chart and image version. `helm search repo <repo>/<chart>` or
  `helm show chart <oci url>` gives the latest.
- When something's stuck: `kubectl --context k3d-dev describe` it (`d`, or
  sofka's `X`), then
  `flux --context k3d-dev events -A`. The repo README's Troubleshooting table
  covers the platform.

## Planned lessons

In order, after 16. Each still needs writing in the usual layout.

| # | Lesson | You end up with | Uses |
| --- | --- | --- | --- |
| 17 | Policy and supply chain | Pod Security Admission labels on every namespace; Kyverno or the built-in `ValidatingAdmissionPolicy`, audit then enforce; mirrored images signed with cosign and refused unsigned | 5, 8, 9 |
| 18 | IRSA against a real AWS account | An AWS account (root MFA, no root keys, IAM Identity Center, `aws sso login`, a budget alarm); the cluster's service account issuer published to S3 as an IAM OIDC provider; pods assuming roles with `AssumeRoleWithWebIdentity`; what Pod Identity changes on EKS. A k3s argument change, so `kube-delete` / `kube-create` | 2, 5 |
| 19 | Upgrade drill | An alert on `apiserver_requested_deprecated_apis`, the signal EKS cluster insights reads; PDBs and topology spread across the zone labels; drains that respect them; a k3s minor bump, then a Cilium minor, restored from Git | 7, 14 |
| 20 | Platform with kro | A `ResourceGraphDefinition` that onboards a team: namespace, quota, `LimitRange`, RBAC, a Flux tenant `Kustomization`, mesh enrolment and policy by default. EKS Capabilities runs kro managed | 12, 17 |

## More lessons

Each is one or two charts and a clear thing to learn.

| Area | Idea |
| --- | --- |
| GitOps | **Flux notifications**: `Provider` and `Alert` objects posting reconcile failures to Discord or Slack. |
| Security | **Tetragon**: Cilium's eBPF runtime security. Trace process execs and file access in pods. |
| Security | **Trivy Operator**: vulnerability and config reports as CRDs you can browse in sofka or k9s. |
| Observability | **Loki and Alloy**: logs next to the metrics from lesson 7. |
| Observability | **An always-on eBPF profiler**: Grafana Pyroscope or the OpenTelemetry eBPF profiler, as a DaemonSet beside lesson 7. |
| Observability | **Inspektor Gadget** in lesson 15: the book's BPF tools selected by namespace and pod, as EKS teams run them where there's no shell on the node. |
| Resilience | **VPA with Goldilocks**: requests and limits recommended from real usage. |
