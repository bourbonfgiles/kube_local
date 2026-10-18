# 12. Karpenter on simulated nodes

Karpenter's KWOK provider creates fake nodes instead of EC2 instances. You get
real Karpenter decisions (which node to create, when to consolidate, when to
disrupt) without capacity. Pods on those nodes are reported as running, but
nothing runs.

EKS equivalent: Karpenter with the AWS provider. `NodePool` behaves the same;
`EC2NodeClass` has no local equivalent (here it's `KWOKNodeClass`).

## This one is harder

This is the one lesson that isn't a published chart: there's no released KWOK
build. You build Karpenter from source and push the
image to the local registry, and versions have to line up with Kubernetes 1.36.

## Before you start

- `go`, `ko` (brew) and `kwok` (already in the brewfile).
- The local registry (lesson 7).
- `kubectl config current-context` is `k3d-dev`; the scripts use the current
  context.

## Tasks

1. Clone `kubernetes-sigs/karpenter` and check out a release tag whose
   compatibility matrix includes Kubernetes 1.36.
2. `make install-kwok`: installs the KWOK controller that fakes nodes.
3. Build: `KO_DOCKER_REPO=localhost:5050/karpenter ko build -B --insecure-registry sigs.k8s.io/karpenter/kwok`.
   Note the printed image and digest.
4. `kubectl apply -f kwok/charts/crds`.
5. `helm install karpenter kwok/charts -n kube-system --skip-crds` with
   `controller.image.repository` set to the same path but host
   `k3d-registry.localhost:5000`, plus the tag and digest from task 3.
6. A `KWOKNodeClass` named `default` and a `NodePool` referencing it, with a CPU
   limit (say 64).
7. A Deployment of `pause` pods, each requesting 1 CPU, that only tolerates
   and selects Karpenter's nodes. Scale it to 20.
8. k9s `:nodeclaims` and `:nodes`: watch nodes appear, and see which
   instance types Karpenter picks.
9. Scale to 2 and watch consolidation remove nodes. Try
   `disruption.consolidationPolicy` and `budgets`.
10. Move it into Flux: a `GitRepository` on the Karpenter repo at your tag, and
    a `HelmRelease` with `chart: ./kwok/charts` from that source.

## Done when

- You can explain why Karpenter chose the nodes it did, and predict what
  consolidation will do.

## Where it gets hard

- The image name ko pushes (`localhost:5050/...`) isn't the one pods pull
  (`k3d-registry.localhost:5000/...`). Same image, different host.
- DaemonSets (Cilium's agent, for one) get scheduled onto the fake nodes and
  report as running. Ignore them, or keep them off with node affinity.
- Keep Karpenter itself and your real workloads off fake nodes: they'd be
  "running" nowhere.
- Delete NodePools and NodeClaims before uninstalling, or the finalizers hang.

## Links

- <https://github.com/kubernetes-sigs/karpenter/tree/main/kwok>
- <https://karpenter.sh/docs/concepts/nodepools/>
- <https://karpenter.sh/docs/concepts/disruption/>
- <https://kwok.sigs.k8s.io/>
