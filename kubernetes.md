# Local Kubernetes

A single k3d cluster (`dev`) on rootful Podman that emulates a naked EKS cluster
closely enough to learn Flux, Cilium, Gateway API, cert-manager, external-dns
and Karpenter without cloud spend. Cluster shape lives in the dotfiles repo;
everything installed onto it lives here.

## What it achieves

- A cluster that boots with no CNI and no service routing, like a managed
  cluster before its add-ons, so the install order is explicit.
- Cilium as the entire network layer (CNI, kube-proxy replacement, L2
  load-balancing, Gateway API, Hubble) for eBPF and tracing study.
- A clean handoff: the bootstrap stops once networking works. Whatever GitOps
  tool comes next (Flux now, maybe Argo CD later) takes over from there.

## Local vs cloud

| Path | Holds |
| --- | --- |
| `cilium/values.yaml` | Settings you'd also use on EKS. |
| `overlays/local/` | Everything that only exists because this is k3d. |

Helm merges the base values and then `overlays/local/cilium-values.yaml`, so no
Kustomize is involved.

## Cluster shape (dotfiles: `~/.config/k3d/config.yaml`)

| Decision | Why |
| --- | --- |
| 1 server + 3 agents | EKS hides the control plane; workloads only see the agents. |
| `--cluster-init` | Embedded etcd on the server, the datastore EKS uses, not SQLite. |
| Control-plane `NoSchedule` taint | Workloads land only on agents, as on EKS. |
| flannel, kube-proxy, servicelb, traefik, network-policy all disabled | Cilium provides all of it; nothing competes with it. |
| Region/zone/instance-type/nodegroup labels (`eu-west-2`, a/b/c, `m5.large`, `general`) | Topology-spread and affinity manifests behave as they would on EKS. |
| k3s pinned to 1.36 | A minor EKS offers in standard support (until Aug 2027). |
| Rootful Podman | Cilium loads BPF programs; atomic Fedora disables unprivileged BPF. |
| No host bpffs mount | Each node gets its own bpffs; a shared one would collide pinned maps. |

## Networking: Cilium 1.20

1.20 is the first minor whose compatibility matrix includes Kubernetes 1.36
(1.18 stops at 1.33).

Base (`cilium/values.yaml`):

- `kubeProxyReplacement: true`: Cilium implements Services in eBPF.
- `gatewayAPI.enabled: true`: the ingress direction now ingress-nginx is retired.
  Not the chart default.
- Hubble (relay + UI) and `bpf.monitorAggregation: none`: full flow visibility
  and unaggregated trace events.

Local overlay (`overlays/local/cilium-values.yaml`):

- `k8sServiceHost: k3d-dev-serverlb` / 6443: no kube-proxy, so Cilium needs the
  API server address directly.
- `routingMode: tunnel` (vxlan): k3d doesn't install pod CIDR routes on nodes.
- L2 announcements + `lb-ipam.yaml`: stand in for a cloud load balancer.
  `type: LoadBalancer` services get an IP in `10.89.0.200-250` that the host can
  reach.
- `cgroup.autoMount.enabled: false`, `cgroup.hostRoot: /sys/fs/cgroup`: k3d nodes
  don't propagate mounts, so an auto-mounted cgroup2 never reaches the agent and
  socket-LB hooks attach where no pod lives (ClusterIPs then fail with
  `network is unreachable`). If you change this on a running cluster, rebuild
  it: Cilium reuses its pinned hooks across restarts.
- `operator.replicas: 1`.

## Bootstrap

`overlays/local/bootstrap.sh`, the only imperative step:

1. Apply the Gateway API v1.6.3 CRDs. They must exist before the Cilium operator
   starts, or it disables Gateway API until restarted.
2. `helm upgrade --install` Cilium with base + local values, pinned to the
   `k3d-dev` kube-context so it can't land anywhere else.
3. Wait for Cilium and Ready nodes, then apply the LB-IPAM pool.

Re-runnable. Flux (or Argo CD) is installed by hand afterwards; see README.md.

GitOps tools reconcile from the pushed remote branch, not from this checkout.
`bootstrap.sh` reads local files; Flux only sees what's on GitHub.

## Working with the cluster

k3d writes the `k3d-dev` context into `~/.kube/config` and makes it current.
Pass `--context k3d-dev` (or `--kube-context` for helm) whenever you also have
work contexts, so nothing lands on the wrong cluster.

| To | Run |
| --- | --- |
| Poke at resources | `kubectl`, `k9s` |
| See the node containers | `kpodman ps` (plain `podman` is rootless and shows nothing) |
| Cilium health | `cilium status --context k3d-dev` |
| Live flows | `cilium hubble port-forward &` then `hubble observe -f` |
| Hubble UI | `cilium hubble ui` |
| Reach a LoadBalancer/Gateway | Its `10.89.0.2xx` address, straight from the host |

## Getting started with Flux

Flux pulls from GitHub, not from this checkout. Push before expecting a change.

### If you know Argo CD

| Argo CD | Flux |
| --- | --- |
| `Application` (Git path) | `GitRepository` + `Kustomization` (Flux's sync object, not Kustomize overlays) |
| `Application` (Helm chart) | `HelmRepository`/`OCIRepository` + `HelmRelease` |
| repo-server | source-controller |
| App of apps | A `Kustomization` whose path contains more `Kustomization`s |
| Sync / auto-sync | Continuous by `interval`; force with `flux reconcile` |
| Disable auto-sync | `flux suspend` / `flux resume` |
| Prune, health checks | `prune: true`, `wait: true` |
| UI | None built in; use `flux get`, `flux events`, `k9s` |

There is no Kustomize unless you add a `kustomization.yaml` yourself. A Flux
`Kustomization` pointed at a plain directory applies every manifest in it.

### 1. Bootstrap

Create a fine-grained GitHub token scoped to `kube_local` with Administration
read/write (bootstrap adds an SSH deploy key), Contents read/write, and
Metadata read.

```sh
flux check --pre --context k3d-dev
export GITHUB_TOKEN=...
flux bootstrap github --context k3d-dev \
  --owner bourbonfgiles --repository kube_local --personal --private=false \
  --branch feature/bootstrap --path clusters/dev
git pull
```

`--private=false` because the repo is public; without it bootstrap assumes a
private repo. Bootstrap installs the controllers into `flux-system`, commits
`clusters/dev/flux-system/`, and creates a `GitRepository` and a `Kustomization`,
both named `flux-system`, that sync `clusters/dev`. From here, anything committed
under `clusters/dev/` gets applied.

```sh
flux get all -A
flux events -A
```

### 2. First HelmRelease, exposed through the Gateway

`clusters/dev/podinfo.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: podinfo
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: podinfo
spec:
  interval: 1h
  url: oci://ghcr.io/stefanprodan/charts/podinfo
  ref:
    semver: "6.x"
---
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
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web
  namespace: podinfo
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: podinfo
  namespace: podinfo
spec:
  parentRefs:
    - name: web
  rules:
    - backendRefs:
        - name: podinfo
          port: 9898
```

```sh
git add clusters/dev/podinfo.yaml && git commit -m "podinfo" && git push
flux reconcile kustomization flux-system --with-source
flux get helmreleases -A
curl "http://$(kubectl -n podinfo get gateway web -o jsonpath='{.status.addresses[0].value}')"
```

Then change something in Git (`spec.values.replicaCount: 3`), push, and watch
helm-controller roll it out. Delete the HTTPRoute with `kubectl` and the next
reconcile puts it back. Deleting the Deployment doesn't, unless you set
`spec.driftDetection.mode: enabled` on the HelmRelease. That's the Flux
equivalent of Argo's self-heal for Helm charts.

### 3. Make Flux own Cilium

Add a `HelmRepository` for `https://helm.cilium.io` and a `HelmRelease` named
`cilium` in `kube-system`, pinned to the same version as
`overlays/local/bootstrap.sh`. Same name and namespace means helm-controller
takes over the release bootstrap made instead of installing a second one.

Values have to come from the HelmRelease itself: `valuesFrom` reads ConfigMaps
and Secrets, not files in Git. Either inline both values files (base first, then
local), or commit them as two ConfigMaps and list both under `valuesFrom` in
that order. The ConfigMap route keeps one copy, but then `bootstrap.sh` has to
read the same ConfigMaps.

Leave `k8sServiceHost` in the values. If Flux drops it, Cilium loses the API
server and the cluster's networking goes down.

### Day 2

```sh
flux get kustomizations -A      # is the sync healthy?
flux logs -A --level=error       # what failed?
flux diff kustomization flux-system --path clusters/dev   # what would change?
flux trace -n podinfo deployment podinfo                   # which Flux object owns this?
flux suspend helmrelease cilium -n kube-system             # stop reconciling while you experiment
flux resume helmrelease cilium -n kube-system
```

Starting over: rebuild the cluster, run `bootstrap.sh`, and run the same
`flux bootstrap` command again. It reuses what's already in Git. `flux uninstall`
removes Flux but leaves the deploy key in the GitHub repo settings.

## Registry

- Persistent standalone k3d registry (created by the dotfiles, not the
  cluster), so the image cache survives `k3d cluster delete`.
- Push from the host to `localhost:5050` (`--tls-verify=false` with Podman).
- In manifests use `k3d-registry.localhost:5050/...` or
  `k3d-registry.localhost:5000/...`; both are mirrored on the nodes.
  `localhost:5050` does not work from pods.

## Deliberate EKS-fidelity gaps

Handled later via GitOps, not emulated in the cluster itself:

- **IRSA / Pod Identity**: no AWS IAM locally; use static creds or the Pod
  Identity webhook when needed.
- **external-dns**: LocalStack Route53, so the provider config matches EKS.
- **Storage**: a local-path StorageClass aliased `gp3` with
  `WaitForFirstConsumer`; no real EBS.
- **Karpenter**: the KWOK provider; its AWS `EC2NodeClass` fields don't apply.
- **Load balancers**: L2 announcements instead of an AWS NLB/ALB.

## Environment-specific values to verify

- The LB-IPAM range must sit inside the k3d network:
  `podman --url $DOCKER_HOST network inspect k3d-dev`.
- `GITHUB_TOKEN` exported before `flux bootstrap`.
