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
