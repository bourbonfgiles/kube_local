# 11. Event-driven scaling with KEDA

> You end up with: the shop's `accounting` consumer scaling out when Kafka lag
> builds up and back in when it clears, instead of on CPU.

## What it is

The Horizontal Pod Autoscaler scales on metrics the cluster already has,
usually CPU. A queue worker's real signal is how much work is waiting, which
lives outside Kubernetes. **KEDA** bridges that: it reads event sources
(Kafka lag, SQS depth, a Prometheus query, a cron schedule) and feeds them to
an HPA it manages for you.

| Piece | Does |
| --- | --- |
| `ScaledObject` | "Scale this Deployment on these triggers, between min and max replicas" |
| Scaler | One per trigger type. The `kafka` scaler reads a consumer group's lag. |
| keda-operator | Creates and owns the HPA, and scales between 0 and 1 itself |
| keda-operator-metrics-apiserver | Serves the trigger values to the HPA through the external metrics API |

```mermaid
flowchart LR
  checkout["checkout"] -->|"produce"| topic["Kafka topic orders"]
  topic -->|"consume, group accounting"| acc["Deployment accounting"]
  so["ScaledObject accounting"] --> op["keda-operator"]
  op -->|"read lag"| topic
  op -->|"creates"| hpa["HPA keda-hpa-accounting"]
  ms["metrics apiserver"] -->|"lag as external metric"| hpa
  hpa -->|"replicas"| acc
```

The split matters: the HPA does 1 to N; only KEDA can go to and from 0,
because an HPA can't scale something with no pods to measure.

## On EKS

KEDA on SQS queue depth or MSK consumer lag is the standard pattern for queue
workers, with the scaler authenticating through an IAM role
(`TriggerAuthentication` with `podIdentity`).

## Requirements

**In the cluster**: the OpenTelemetry Demo in `otel-demo` (lesson 10), and
`metrics-server` (k3s ships it; `kubectl --context k3d-dev top nodes` works).

**On your machine**: `kubectl`, `helm`, `flux`, and `sofka`
or `k9s` ([lesson 0](00-tools.md)).

## By hand, for comparison

> [!NOTE]
> Read this, don't run it. Flux does the same from Git below.

**Example only: don't run it**
```sh
helm --kube-context k3d-dev upgrade --install keda keda --repo https://kedacore.github.io/charts \
  --version 2.21.0 -n keda --create-namespace
kubectl --context k3d-dev apply -f scaledobject.yaml
```

## Install with Flux

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `keda` | `~/repos/personal/kube_local/infrastructure/base/keda/namespace.yaml` |
| HelmRepository | `kedacore` | `~/repos/personal/kube_local/infrastructure/base/keda/source.yaml` |
| HelmRelease | `keda` | `~/repos/personal/kube_local/infrastructure/base/keda/release.yaml` |
| ScaledObject | `otel-demo/accounting` | `~/repos/personal/kube_local/apps/base/otel-demo/scaledobject.yaml` |

No values ConfigMaps: KEDA's defaults are fine.

### 1. KEDA

```sh
mkdir -p ~/repos/personal/kube_local/infrastructure/base/keda
```

**Write `~/repos/personal/kube_local/infrastructure/base/keda/namespace.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/keda/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: keda
```

**Write `~/repos/personal/kube_local/infrastructure/base/keda/source.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/keda/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kedacore
  namespace: keda
spec:
  interval: 1h
  url: https://kedacore.github.io/charts
```

**Write `~/repos/personal/kube_local/infrastructure/base/keda/release.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/keda/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: keda
  namespace: keda
spec:
  interval: 10m
  chart:
    spec:
      chart: keda
      version: 2.21.0
      sourceRef:
        kind: HelmRepository
        name: kedacore
```

Push it first: `apps-base` can't apply a ScaledObject until KEDA's CRDs
exist, and nothing else in `apps-base` applies meanwhile.

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/infrastructure/
git -C ~/repos/personal/kube_local commit -m "KEDA with Flux"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
kubectl --context k3d-dev get helmreleases -n keda -w
```

### 2. The consumer and its topic

The Kafka tools live in `/opt/kafka/bin`, which isn't on the image's PATH:

```sh
kubectl --context k3d-dev -n otel-demo exec deploy/kafka -- \
  /opt/kafka/bin/kafka-topics.sh --describe --topic orders --bootstrap-server localhost:9092
kubectl --context k3d-dev -n otel-demo exec deploy/kafka -- \
  /opt/kafka/bin/kafka-consumer-groups.sh --describe --group accounting --bootstrap-server localhost:9092
```

Note the partition count; step 2 below goes past it.

sofka / k9s: `:pods otel-demo`, `s` on `kafka`.

### 3. The ScaledObject

**Write `~/repos/personal/kube_local/apps/base/otel-demo/scaledobject.yaml`**
```yaml
# ~/repos/personal/kube_local/apps/base/otel-demo/scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: accounting
  namespace: otel-demo
spec:
  scaleTargetRef:
    name: accounting
  minReplicaCount: 1
  maxReplicaCount: 3
  cooldownPeriod: 60
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka.otel-demo.svc:9092
        consumerGroup: accounting
        topic: orders
        lagThreshold: "10"
```

```sh
git -C ~/repos/personal/kube_local pull
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/apps/base/otel-demo/scaledobject.yaml
git -C ~/repos/personal/kube_local commit -m "Scale accounting on Kafka lag"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization apps-base --with-source
kubectl --context k3d-dev get scaledobjects,hpa -n otel-demo
```

KEDA created `keda-hpa-accounting` from it.

sofka / k9s: `:scaledobjects otel-demo`, then `:hpa otel-demo`. sofka
extra ([lesson 0](00-tools.md)): `X` on the ScaledObject if it isn't ready.

## Iterate

Keep these running, each in its own terminal:

```sh
kubectl --context k3d-dev -n otel-demo get hpa keda-hpa-accounting -w   # terminal 1
kubectl --context k3d-dev -n keda logs deploy/keda-operator -f          # terminal 2
```

sofka / k9s: `:hpa otel-demo`; `:pods keda`, `l` on `keda-operator`.
sofka extras: `T` on `accounting` timestamps each replica change, and
`ctrl-z` in the logs leaves only the errors.

| Try | Then look at |
| --- | --- |
| Raise the users at `/loadgen/`, or turn on `kafkaQueueProblems` in `/feature/` | The HPA's current value climbs past the target, and `accounting` scales out |
| Drop the load the same way | Scale-in after `cooldownPeriod` plus the HPA's own stabilisation |

### Changes worth knowing

Each row is one commit, then its revert. What happens is the point; try any you like.

Every row changes the ScaledObject in `~/repos/personal/kube_local/apps/base/otel-demo/scaledobject.yaml`, with
the load up.

| Change | What happens |
| --- | --- |
| `lagThreshold: "2"` (from `"10"`) | Scales out much sooner. |
| `maxReplicaCount: 6` (from 3) | Consumers past the partition count get no partition, so lag falls no faster. |
| `minReplicaCount: 0` (from 1) | Zero when idle. KEDA, not the HPA, takes it from 0 to 1; meanwhile orders wait in Kafka. |

## Exercises

1. Explain the numbers in `describe hpa` (or `d`): target, current, and how KEDA turned
   lag into them.
2. Add a second trigger, `cron`, holding 2 replicas during "business hours".
   KEDA takes the maximum of all triggers.
3. Watch `accounting` scale while Chaos Mesh (lesson 14) kills its pods.
4. Harder: the same scaling from a `prometheus` trigger on the demo's own
   Kafka metrics instead of the `kafka` scaler, and compare how quickly each
   reacts.

## Where it gets hard

- Flux and KEDA both want to set replicas. If the demo's HelmRelease has drift
  detection on, ignore `/spec/replicas` for Deployments (lesson 9), or they
  fight.
- Don't add your own HPA for the same Deployment; KEDA owns it.
- Consumers beyond the partition count do nothing.
- A wrong `bootstrapServers` or `consumerGroup` doesn't fail loudly: the
  ScaledObject goes not-ready and the reason is in the keda-operator's logs.
  sofka's `X` on the ScaledObject ([lesson 0](00-tools.md)) shows its `Ready` message first, which is
  often enough.

## Links

- <https://keda.sh/docs/latest/concepts/scaling-deployments/>
- <https://keda.sh/docs/latest/scalers/apache-kafka/>
- <https://fluxcd.io/flux/components/helm/helmreleases/#drift-detection>
