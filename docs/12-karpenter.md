# 12. Karpenter on simulated nodes

> You end up with: Karpenter creating and removing nodes as pods come and go,
> making the same decisions it would on EKS, on fake nodes that cost nothing.

## What it is

Karpenter is a node autoscaler. When pods can't be scheduled, it works out
what nodes would fit them, picks the cheapest instance types that do, and
creates them. When nodes are underused, it moves pods off and removes them
(**consolidation**). Unlike the Cluster Autoscaler, it doesn't scale fixed
node groups: it chooses each node's shape per decision.

| Kind | Says |
| --- | --- |
| `NodePool` | What nodes may be created: requirements (arch, zones, instance families), taints, a CPU/memory limit, and disruption rules |
| `NodeClass` | Cloud-specific settings for those nodes. `EC2NodeClass` on AWS (AMI, subnets, security groups); `KWOKNodeClass` here |
| `NodeClaim` | One node Karpenter decided to create. It becomes a `Node` once the provider delivers it |

```mermaid
flowchart LR
  pending["Pods Pending<br/>(no node fits)"] --> k["Karpenter"]
  k -->|"bin-pack, pick cheapest types"| nc["NodeClaim"]
  nc --> prov["Provider<br/>EC2 on AWS, KWOK here"]
  prov --> node["Node"]
  node --> sched["Scheduler binds the pods"]
  k -.->|"underused nodes"| cons["Consolidation:<br/>cordon, drain, delete"]
```

**KWOK** (Kubernetes WithOut Kubelet) fakes nodes: they register, report
capacity and show pods as running, but nothing actually runs. Karpenter's KWOK
provider uses it in place of EC2, with a catalogue of made-up instance types.

> [!IMPORTANT]
> This is the one lesson without a published chart or image. There's no
> released KWOK build of Karpenter: you build its image from source with `ko`,
> push it to the local registry, and install the chart from the source tree.

## On EKS

Karpenter with the AWS provider, its published chart, an `EC2NodeClass`, and
an IAM role to launch instances. The `NodePool` and disruption behaviour you
learn here carry over unchanged.

## Requirements

**In the cluster**: Flux, `infra-local-config` (lesson 4) and the local
registry (lesson 7).

**On your machine**: `git`, `go`, `ko`, `kwok`, `make`, `kubectl`, `helm`,
`flux`, and `sofka` or `k9s` ([lesson 0](00-tools.md)).

## By hand, for comparison

> [!NOTE]
> Read this, don't run it. Flux installs the chart from Karpenter's Git repo
> below.

By hand, the chart installs from the clone, with the CRDs first and the build's
tag and digest on the command line:

**Example only: don't run it**
```sh
kubectl --context k3d-dev apply -f ~/repos/personal/karpenter/kwok/charts/crds
helm --kube-context k3d-dev upgrade --install karpenter ~/repos/personal/karpenter/kwok/charts -n kube-system \
  --skip-crds -f ~/repos/personal/karpenter/karpenter-values.yaml \
  --set controller.image.tag="$KARPENTER_VERSION" \
  --set controller.image.digest="$DIGEST"
```

`karpenter-values.yaml` holds the Makefile's `HELM_OPTS` and `install-kwok`
settings:

**Example only: it goes in a ConfigMap below**
```yaml
# ~/repos/personal/karpenter/karpenter-values.yaml
logLevel: debug
settings:
  preferencePolicy: Ignore
  featureGates:
    nodeRepair: true
    capacityBuffer: true
    staticCapacity: true
controller:
  image:
    repository: k3d-registry.localhost:5000/karpenter/kwok   # the name pods pull by
  resources:
    requests: {cpu: 500m, memory: 512Mi}
    limits: {memory: 1Gi}
```

## Install with Flux

Everything is local: on EKS you'd use the AWS provider's published chart
instead.

| Kind | Name | File |
| --- | --- | --- |
| GitRepository | `kube-system/karpenter` | `~/repos/personal/kube_local/infrastructure/local/karpenter/source.yaml` |
| HelmRelease | `kube-system/karpenter` | `~/repos/personal/kube_local/infrastructure/local/karpenter/release.yaml` |
| ConfigMap | `kube-system/karpenter-values-local` | `~/repos/personal/kube_local/infrastructure/local/karpenter/values.yaml` |
| KWOKNodeClass, NodePool | `default` | `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml` |
| Deployment | `default/inflate` | `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`: test load, removed at the end |
| KWOK controller, image | | Commands: steps 2 and 3, again after a rebuild |

Steps 1 to 3 work on a clone of Karpenter in `~/repos/personal/karpenter`. Its
Makefile uses your *current* context, so set it first:

```sh
kubectl config use-context k3d-dev
git clone https://github.com/kubernetes-sigs/karpenter ~/repos/personal/karpenter
```

### 1. A version that supports Kubernetes 1.36

```sh
git -C ~/repos/personal/karpenter tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head
KARPENTER_VERSION=$(git -C ~/repos/personal/karpenter tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "$KARPENTER_VERSION"
```

Check the compatibility matrix in its docs supports 1.36 at that version. If
it doesn't, set `KARPENTER_VERSION` to one from the list that does. Then:

```sh
git -C ~/repos/personal/karpenter checkout "$KARPENTER_VERSION"
```

### 2. The KWOK controller

```sh
make -C ~/repos/personal/karpenter install-kwok
```

### 3. Build and push the image

```sh
cd ~/repos/personal/karpenter   # ko builds the Go module it's in
KO_DOCKER_REPO=localhost:5050/karpenter ko build -B --tags "$KARPENTER_VERSION" \
  --insecure-registry sigs.k8s.io/karpenter/kwok
DIGEST=$(skopeo inspect --tls-verify=false \
  docker://localhost:5050/karpenter/kwok:"$KARPENTER_VERSION" | jq -r .Digest)
echo "$DIGEST"
cd ~/repos/personal
```

The image is tagged with the Karpenter version, and `DIGEST` pins it.

### 4. The chart, from Git

The chart comes from Git, not a chart repository, at the tag from step 1.
Flux installs the chart's `crds/` itself. The values ConfigMap holds the
values above plus the image's tag and digest.

The tag and digest come from your build, so set them again (a new shell
loses them) and write the source and values from them:

```sh
KARPENTER_VERSION=$(git -C ~/repos/personal/karpenter describe --tags --exact-match)
DIGEST=$(skopeo inspect --tls-verify=false \
  docker://localhost:5050/karpenter/kwok:"$KARPENTER_VERSION" | jq -r .Digest)
mkdir -p ~/repos/personal/kube_local/infrastructure/local/karpenter
```

**Write `~/repos/personal/kube_local/infrastructure/local/karpenter/source.yaml`**
```sh
cat > ~/repos/personal/kube_local/infrastructure/local/karpenter/source.yaml <<EOF
# ~/repos/personal/kube_local/infrastructure/local/karpenter/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: karpenter
  namespace: kube-system
spec:
  interval: 1h
  url: https://github.com/kubernetes-sigs/karpenter
  ref:
    tag: ${KARPENTER_VERSION}
EOF
```

**Write `~/repos/personal/kube_local/infrastructure/local/karpenter/values.yaml`**
```sh
cat > ~/repos/personal/kube_local/infrastructure/local/karpenter/values.yaml <<EOF
# ~/repos/personal/kube_local/infrastructure/local/karpenter/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: karpenter-values-local
  namespace: kube-system
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    logLevel: debug
    settings:
      preferencePolicy: Ignore
      featureGates:
        nodeRepair: true
        capacityBuffer: true
        staticCapacity: true
    controller:
      image:
        repository: k3d-registry.localhost:5000/karpenter/kwok   # the name pods pull by
        tag: ${KARPENTER_VERSION}
        digest: ${DIGEST}
      resources:
        requests: {cpu: 500m, memory: 512Mi}
        limits: {memory: 1Gi}
EOF
```

```sh
cat ~/repos/personal/kube_local/infrastructure/local/karpenter/source.yaml ~/repos/personal/kube_local/infrastructure/local/karpenter/values.yaml
```

The release has nothing build-specific:

**Write `~/repos/personal/kube_local/infrastructure/local/karpenter/release.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local/karpenter/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: karpenter
  namespace: kube-system
spec:
  interval: 10m
  chart:
    spec:
      chart: ./kwok/charts
      sourceRef:
        kind: GitRepository
        name: karpenter
  valuesFrom:
    - kind: ConfigMap
      name: karpenter-values-local
```

### 5. A node class and a pool

The NodePool needs Karpenter's CRDs, so it goes in `infra-local-config`
(lesson 4). The taint keeps everything that doesn't ask for fake nodes off
them:

```sh
mkdir -p ~/repos/personal/kube_local/infrastructure/local-config/karpenter
```

**Write `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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

### 6. Push and check

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/
git -C ~/repos/personal/kube_local commit -m "Karpenter with Flux"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
kubectl --context k3d-dev get helmreleases -n kube-system karpenter -w
kubectl --context k3d-dev get nodepools
```

## Iterate

A test load in Git, removed at the end. Its replica count is what makes
Karpenter act:

```sh
mkdir -p ~/repos/personal/kube_local/apps/local/inflate
```

**Write `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  replicas: 20
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter test load: 20"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

```sh
kubectl --context k3d-dev describe nodeclaims
```

Each NodeClaim shows the instance type Karpenter chose and why.

sofka / k9s: `:nodeclaims`, `:nodes`, `d` on a NodeClaim

When pods stay `Pending`, find them, ask why, and see what each node has
promised and what Karpenter thinks:

```sh
kubectl --context k3d-dev -n default get pods --field-selector=status.phase=Pending
kubectl --context k3d-dev -n default describe pods -l app=inflate
kubectl --context k3d-dev describe nodes -l karpenter.sh/nodepool=default   # Allocated resources
kubectl --context k3d-dev -n kube-system logs deploy/karpenter -f
```

sofka / k9s: `ctrl-z` on `:pods -n default`, `d` on a pod or node;
`:pods -n kube-system`, `l` on `karpenter`. sofka extras: `X` on a pod, and
`:nodes` has `%CPU/R`.

> [!TIP]
> A sofka extra ([lesson 0](00-tools.md)): `X` on a node checks Ready,
> cordon, taints and pod capacity. On a fake node it shows the `kwok` taint,
> and during consolidation, the cordon Karpenter put on before draining it.

New or changed lines sit between `# ── new ──` and `# ── end new ──`.

### 1. Consolidation, default policy

**Replace `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  # ── new ──
  replicas: 2
  # ── end new ──
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter test load: 2"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

`WhenEmptyOrUnderutilized`: nodes go, and pods may be moved to pack the rest.

### 2. Only empty nodes go

**Replace `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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
  # ── new ──
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
  # ── end new ──
  limits:
    cpu: 64
```

**Replace `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  # ── new ──
  replicas: 20
  # ── end new ──
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter: WhenEmpty, load 20"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

Once the nodes are up, back to 2:

**Replace `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  # ── new ──
  replicas: 2
  # ── end new ──
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter test load: 2"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

Empty nodes go; half-empty ones stay.

### 3. A CPU limit on the pool

**Replace `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
  limits:
    # ── new ──
    cpu: 8
    # ── end new ──
```

**Replace `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  # ── new ──
  replicas: 20
  # ── end new ──
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter: 8 CPU limit, load 20"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev -n default get pods --field-selector=status.phase=Pending
kubectl --context k3d-dev get events -A --field-selector involvedObject.kind=NodePool
```

Some pods stay `Pending`, and the events say the limit was hit. Back to 64:

**Replace `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
  limits:
    # ── new ──
    cpu: 64
    # ── end new ──
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter: 64 CPU limit"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

### 4. One node at a time

**Replace `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
    # ── new ──
    budgets:
      - nodes: "1"
    # ── end new ──
  limits:
    cpu: 64
```

**Replace `~/repos/personal/kube_local/apps/local/inflate/inflate.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  # ── new ──
  replicas: 2
  # ── end new ──
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      tolerations:
        - key: kwok
          operator: Exists
          effect: NoSchedule
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml ~/repos/personal/kube_local/apps/local/inflate/inflate.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter: one node at a time, load 2"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization infra-local-config
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

Consolidation removes one node at a time.

### 5. Remove the test load

The NodePool goes back to step 5's, and `inflate` leaves Git:

**Replace `~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
apiVersion: karpenter.kwok.sh/v1alpha1
kind: KWOKNodeClass
metadata:
  name: default
---
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

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local rm -r ~/repos/personal/kube_local/apps/local/inflate
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/local-config/karpenter/nodepool.yaml
git -C ~/repos/personal/kube_local commit -m "Karpenter: drop the test load"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
flux --context k3d-dev reconcile kustomization apps-local
kubectl --context k3d-dev get nodeclaims,nodes -w
```

`prune` deletes `inflate`, and Karpenter removes the empty nodes.

## Exercises

1. Explain why Karpenter chose the instance types it did for 20 pods of 1 CPU,
   then for 20 pods of 3 CPU.
2. Two NodePools with different `weight`s and requirements, and see which wins.
3. Spread `inflate` across zones with a `topologySpreadConstraint`, and watch
   Karpenter create nodes in each.
4. Harder: set `expireAfter: 5m` on the NodePool and watch drift and
   expiration replace nodes while a PodDisruptionBudget limits how many
   `inflate` pods can be down at once.

## Where it gets hard

- The name ko pushes (`localhost:5050/...`) isn't the one pods pull
  (`k3d-registry.localhost:5000/...`). Same image, two hosts.
- DaemonSets that tolerate every taint (Cilium's agent, for one) land on the
  fake nodes and show as running. Ignore them.
- Keep real workloads off fake nodes: they'd be "running" nowhere. The taint
  does that.
- Delete NodePools and NodeClaims before uninstalling, or their finalizers
  hang.
- Versions must line up: the Karpenter tag, its KWOK provider and Kubernetes
  1.36.

## Links

- <https://karpenter.sh/docs/concepts/>
- <https://github.com/kubernetes-sigs/karpenter/tree/main/kwok>
- <https://karpenter.sh/docs/concepts/disruption/>
- <https://kwok.sigs.k8s.io/>
