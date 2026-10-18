# 12. Karpenter on simulated nodes

Karpenter's KWOK provider creates fake nodes instead of EC2 instances. You get
real Karpenter decisions (which node to create, when to consolidate, when to
disrupt) without capacity. Pods on those nodes are reported as running, but
nothing runs.

EKS equivalent: Karpenter with the AWS provider. `NodePool` behaves the same;
`EC2NodeClass` has no local equivalent (here it's `KWOKNodeClass`).

## This one is harder

This is the one lesson without a published chart or image: there's no
released KWOK build. You build Karpenter's image from source with `ko`, push
it to the local registry, and install its chart from the source tree. Versions
have to line up with Kubernetes 1.36.

## Before you start

On your machine: `git`, `go`, `ko`, `kwok`, `make`, `kubectl`, `helm`, `flux`.

In the cluster: Flux (lesson 2) and the local registry (lesson 7).

## Objects

Everything is local: on EKS you'd install the AWS provider's published chart
instead.

| Kind | Name | File |
| --- | --- | --- |
| KWOK controller | `kwok-controller` | By hand, `make install-kwok` |
| GitRepository | `kube-system/karpenter` | `infrastructure/local/karpenter/source.yaml` |
| HelmRelease | `kube-system/karpenter` | `infrastructure/local/karpenter/release.yaml` |
| ConfigMap | `kube-system/karpenter-values-local` | `infrastructure/local/karpenter/values.yaml` |
| KWOKNodeClass | `default` | `infrastructure/local-config/karpenter/nodeclass.yaml` |
| NodePool | `default` | `infrastructure/local-config/karpenter/nodepool.yaml` |
| Deployment | `default/inflate` | `demo/inflate.yaml`, by hand only |

## Tasks

Tasks 1-4 run in a clone of Karpenter, outside this repo. Its scripts use your
current context, so set it first:

```sh
kubectl config use-context k3d-dev
git clone https://github.com/kubernetes-sigs/karpenter ~/repos/karpenter
```

1. Pick a release tag whose compatibility matrix includes Kubernetes 1.36:
   ```sh
   # in the karpenter clone
   git checkout <tag>
   ```
2. The KWOK controller that fakes nodes:
   ```sh
   # in the karpenter clone
   make install-kwok
   ```
3. Build and push the image. `ko` prints the full reference with its digest:
   ```sh
   # in the karpenter clone
   KO_DOCKER_REPO=localhost:5050/karpenter ko build -B --insecure-registry sigs.k8s.io/karpenter/kwok
   ```
4. Install by hand once, to see it work. These are the settings from the
   Makefile's `HELM_OPTS` and `install-kwok` target, as a values file:
   ```yaml
   # karpenter-values.yaml, in the clone; it becomes the ConfigMap in task 9
   logLevel: debug
   settings:
     preferencePolicy: Ignore
     featureGates:
       nodeRepair: true
       capacityBuffer: true
       staticCapacity: true
   controller:
     image:
       repository: k3d-registry.localhost:5000/karpenter/kwok   # pods pull via this name
       tag: <tag from task 3>
       digest: <sha256 from task 3>
     resources:
       requests: {cpu: 500m, memory: 512Mi}
       limits: {memory: 1Gi}
   ```
   ```sh
   # in the karpenter clone
   kubectl --context k3d-dev apply -f kwok/charts/crds
   helm --kube-context k3d-dev install karpenter kwok/charts -n kube-system \
     --skip-crds -f karpenter-values.yaml
   ```
5. Back in this repo, a node class and a pool. The taint keeps everything
   that doesn't ask for fake nodes off them:
   ```yaml
   # infrastructure/local-config/karpenter/nodeclass.yaml
   apiVersion: karpenter.kwok.sh/v1alpha1
   kind: KWOKNodeClass
   metadata:
     name: default
   ---
   # infrastructure/local-config/karpenter/nodepool.yaml
   apiVersion: karpenter.sh/v1
   kind: NodePool
   metadata:
     name: default
   spec:
     template:
       spec:
         nodeClassRef:
           group: karpenter.kwok.sh
           kind: KWOKNodeClass
           name: default
         taints:
           - key: kwok
             effect: NoSchedule
         requirements:
           - key: kubernetes.io/arch
             operator: In
             values: [amd64]
     limits:
       cpu: 64
   ```
   `kubectl --context k3d-dev apply -f infrastructure/local-config/karpenter/`.
6. Something to schedule: `demo/inflate.yaml`, a Deployment `inflate` of
   `registry.k8s.io/pause:3.10` with `replicas: 0`, `requests.cpu: 1`, a
   toleration for `kwok`, and `nodeSelector: {karpenter.sh/nodepool: default}`.
   Apply it, then:
   ```sh
   kubectl --context k3d-dev scale deployment inflate --replicas 20
   ```
7. k9s `:nodeclaims` and `:nodes`: watch nodes appear, and see which instance
   types Karpenter picks.
8. Scale to 2 and watch consolidation remove nodes. Try
   `disruption.consolidationPolicy` and `disruption.budgets` on the NodePool.
9. Move it into Flux:
   - `helm --kube-context k3d-dev uninstall karpenter -n kube-system`.
   - GitRepository `karpenter`: `url:
     https://github.com/kubernetes-sigs/karpenter`, `ref.tag: <tag>`.
   - HelmRelease `karpenter`: `chart.spec.chart: ./kwok/charts`,
     `sourceRef: {kind: GitRepository, name: karpenter}`, `valuesFrom` the
     ConfigMap `karpenter-values-local` holding `karpenter-values.yaml`. Flux
     installs the chart's CRDs itself.
   - Add `infra-local-config` (lesson 4) if you don't have it yet; the
     NodePool needs Karpenter's CRDs first.
   The KWOK controller and the image stay by hand: rebuilding the cluster
   means tasks 2 and 3 again.

## Done when

- You can explain why Karpenter chose the nodes it did, and predict what
  consolidation will do.

## Where it gets hard

- The image name ko pushes (`localhost:5050/...`) isn't the one pods pull
  (`k3d-registry.localhost:5000/...`). Same image, different host.
- Some DaemonSets (Cilium's agent, for one) tolerate every taint, so they land
  on the fake nodes and report as running. Ignore them.
- Keep Karpenter itself and your real workloads off fake nodes: they'd be
  "running" nowhere. The taint does that.
- Delete NodePools and NodeClaims before uninstalling, or the finalizers hang.

## Links

- <https://github.com/kubernetes-sigs/karpenter/tree/main/kwok>
- <https://karpenter.sh/docs/concepts/nodepools/>
- <https://karpenter.sh/docs/concepts/disruption/>
- <https://kwok.sigs.k8s.io/>
