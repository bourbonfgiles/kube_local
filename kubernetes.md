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
| Fixed Podman network `k3d-dev` (bridge `k3d0`, `10.89.0.0/24`) | Created by dotfiles, so LB IPs and the host DNS route always point at the same place. |
| API server on `127.0.0.1` | Not reachable from the LAN. Port 25565 (Minecraft) still is. |

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
- `ipam.mode: kubernetes`: pods get IPs from the per-node CIDRs k3s assigns
  (`10.42.0.0/16`). Cilium's own default pool, `10.0.0.0/8`, overlaps the node
  network.

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
| Reach a LoadBalancer/Gateway | Its `10.89.0.2xx` address, or its `*.kube.internal` name |

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
  --branch master --path clusters/dev \
  --components-extra image-reflector-controller,image-automation-controller \
  --read-write-key
git pull
```

`--private=false` because the repo is public; without it bootstrap assumes a
private repo. The last two flags are for image promotion later: the image
controllers watch registries, and image automation commits tag bumps back to
Git, which needs a deploy key with write access. Adding them now saves a second
bootstrap. Bootstrap installs the controllers into `flux-system`, commits
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
kind: HTTPRoute
metadata:
  name: podinfo
  namespace: podinfo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames:
    - podinfo.kube.internal
  rules:
    - backendRefs:
        - name: podinfo
          port: 9898
```

```sh
git add clusters/dev/podinfo.yaml && git commit -m "podinfo" && git push
flux reconcile kustomization flux-system --with-source
flux get helmreleases -A
curl http://podinfo.kube.internal/
```

The route attaches to the shared Gateway (see Shared Gateway below), and
ExternalDNS publishes the hostname, so this exercises the whole platform.

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

### 4. Move the rest over, in dependency order

1. `gateway/gateway.yaml`: plain manifests, so a `Kustomization` pointing at
   `./gateway` is enough.
2. DNS: a `Kustomization` for `./overlays/local/dns` and a `HelmRelease` for
   ExternalDNS (both values files, base first). Run `tsig-secret.sh` once by hand
   beforehand. Flux deliberately doesn't create that Secret; encrypting it with
   SOPS so it can live in Git is a good later exercise.
3. Apps: a `HelmRelease` each for Online Boutique and Minecraft, plus the
   boutique route. Use `dependsOn` so they wait for DNS and the Gateway.

Once Flux owns something, change it through Git only. A manual `helm upgrade`
just gets reverted on the next reconcile.

### 5. Image promotion (later)

The pieces are already in place: a registry pods can reach at
`k3d-registry.localhost:5000` (plain HTTP, so set `spec.insecure: true` on the
`ImageRepository`), and the image controllers from bootstrap. The loop:

1. Build and push `localhost:5050/<app>:1.0.0` from the host.
2. `ImageRepository` scans `k3d-registry.localhost:5000/<app>`.
3. `ImagePolicy` picks the newest tag matching a semver range.
4. `ImageUpdateAutomation` commits the new tag into the HelmRelease values,
   wherever a `# {"$imagepolicy": "<ns>:<policy>"}` marker comment sits.

To promote between environments, point a second policy (say `prod`) at a
stricter range, or at tags you only push after testing.

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

## DNS: ExternalDNS writing to a local zone

On EKS, ExternalDNS watches Services and Gateway API routes and writes Route53
records. Here it does the same against BIND, which serves `kube.internal` on
`10.89.0.250`. ExternalDNS sends RFC2136 updates signed with a TSIG key; unsigned
updates are refused.

| Piece | Where | Local only? |
| --- | --- | --- |
| ExternalDNS sources, `sync` policy, TXT registry | `external-dns/values.yaml` | No |
| RFC2136 provider, zone, TSIG | `overlays/local/external-dns-values.yaml` | Yes (Route53 + IRSA on EKS) |
| BIND (the "Route53") | `overlays/local/dns/bind.yaml` | Yes |
| TSIG key | `overlays/local/dns/tsig-secret.sh` creates it; never in Git | Yes |
| Pods resolve `kube.internal` | `overlays/local/dns/coredns-custom.yaml` | Yes |
| Host resolves `kube.internal` | dotfiles `dotfiles-kube-dns.service` (Linux) | Yes |

Install by hand for now (or as your second and third Flux HelmReleases):

```sh
./overlays/local/dns/tsig-secret.sh
kubectl apply -f overlays/local/dns/bind.yaml -f overlays/local/dns/coredns-custom.yaml
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm upgrade --install external-dns external-dns/external-dns \
  --kube-context k3d-dev -n external-dns --version 1.23.0 \
  -f external-dns/values.yaml -f overlays/local/external-dns-values.yaml
```

Then give any HTTPRoute a hostname:

```yaml
spec:
  hostnames:
    - shop.kube.internal
```

Within a minute ExternalDNS writes `shop.kube.internal A <gateway IP>` and a TXT
ownership record. Delete the route and the record goes too (`policy: sync`).

```sh
dig @10.89.0.250 shop.kube.internal              # straight at BIND
dig @10.89.0.250 kube.internal AXFR -y hmac-sha256:externaldns:$(kubectl -n dns get secret externaldns-tsig -o jsonpath='{.data.secret}' | base64 -d)
curl http://shop.kube.internal/                  # once the host route is installed
```

Host resolution on Linux: run the dotfiles k8s step once
(`uv run python -m dotfiles --only k8s`). It installs a systemd unit that, whenever
the `k3d0` bridge exists, tells systemd-resolved to send `*.kube.internal` to
`10.89.0.250` over that link, without DNS-over-TLS or DNSSEC. Everything else
keeps using your normal resolvers. macOS can't reach the Podman VM's bridge IPs,
so there you'd use `kubectl port-forward` instead.

Notes:

- The ExternalDNS RFC2136 host is `bind.dns.svc.cluster.local.` with a trailing
  dot. Without it, Go's resolver walks the pod's five search domains first and
  the zone transfer times out.
- BIND keeps the zone in an `emptyDir`. A restart loses the records and
  ExternalDNS rewrites them on its next sync.
- For the EKS version, swap the overlay for `provider.name: aws` and an IRSA role.
  The base values don't change.

## Shared Gateway

`gateway/gateway.yaml` is the one way into the cluster: a Cilium `Gateway` named
`web` in the `gateway` namespace, listening on HTTP/80 and accepting routes from
any namespace. Apps own their `HTTPRoute`s and attach with:

```yaml
parentRefs:
  - name: web
    namespace: gateway
```

That's the platform/app split Gateway API is built around, and it's the same on
EKS. It usually gets `10.89.0.200`, the first address in the pool.

## Example apps

### Online Boutique (microservices)

Google's demo shop: 11 services in five languages talking gRPC, Redis for the
cart, and a load generator producing steady traffic. That makes it good for
Hubble flows, network policy and BPF tracing.

```sh
helm upgrade --install online-boutique \
  oci://us-docker.pkg.dev/online-boutique-ci/charts/onlineboutique --version 0.10.7 \
  --kube-context k3d-dev -n online-boutique --create-namespace \
  -f apps/online-boutique/values.yaml
kubectl apply -f apps/online-boutique/route.yaml
curl http://shop.kube.internal/
```

Things to try:

- `hubble observe -n online-boutique -f` shows the gRPC fan-out behind each
  page load.
- Network policy: install with `--set networkPolicies.create=true`. Pods
  outside the namespace can no longer reach `redis-cart`, but the shop itself
  starts returning 503. Cilium's Gateway reaches the frontend from its `ingress`
  identity (Hubble shows `(ingress)` as the source), and a plain
  `NetworkPolicy` can't select that. Apply `apps/online-boutique/allow-gateway.yaml`,
  a `CiliumNetworkPolicy` with `fromEntities: [ingress]`, to fix it. Envoy
  refuses the request itself, so this shows up as a 503 rather than a Hubble
  `DROPPED` event.

### Minecraft (Java)

The `itzg/minecraft` chart, vanilla 26.3, with a 5 Gi world on `local-path`.
k3d maps host port 25565 to NodePort 30000, so point a client at this machine's
LAN address.

```sh
helm repo add itzg https://itzg.github.io/minecraft-server-charts/
helm upgrade --install minecraft itzg/minecraft --version 5.2.0 \
  --kube-context k3d-dev -n minecraft --create-namespace \
  -f apps/minecraft/values.yaml -f overlays/local/minecraft-values.yaml
```

- `eula: "TRUE"` in the values means you accept the Minecraft EULA.
- The world lives on the node's disk and goes when the cluster is deleted.
- A JVM with a 2 GB heap is a decent subject for BPF profiling. The values set
  `-XX:+PreserveFramePointer` so stacks stay walkable. Rootful Podman shares
  the host's PID view, so the tools run on the host (the dotfiles `bpf` step
  layers `bpftrace` and the BCC tools):

  ```sh
  PID=$(pgrep -f '^java .*minecraft_server')
  sudo /usr/share/bcc/tools/profile -p "$PID" -F 49 30 > mc.stacks
  sudo /usr/share/bcc/tools/offcputime -p "$PID" 10
  ```

  Java frames show as hex addresses until you add a perf map agent; the BPF
  Performance Tools book's Java chapter covers that.

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
- **Route53**: BIND over RFC2136 instead (see DNS). LocalStack's Route53 DNS
  answering needs a LocalStack account plan, so it was ruled out.
- **Storage**: a local-path StorageClass aliased `gp3` with
  `WaitForFirstConsumer`; no real EBS.
- **Karpenter**: the KWOK provider; its AWS `EC2NodeClass` fields don't apply.
- **Load balancers**: L2 announcements instead of an AWS NLB/ALB.

## Environment-specific values to verify

- The LB-IPAM range must sit inside the k3d network:
  `podman --url $DOCKER_HOST network inspect k3d-dev`.
- `GITHUB_TOKEN` exported before `flux bootstrap`.
