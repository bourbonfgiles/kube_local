# 11. Event-driven scaling with KEDA

The OpenTelemetry Demo is event-driven inside: checkout publishes orders to
the Kafka topic `orders`, and the `accounting` service reads them as consumer
group `accounting`. KEDA scales that consumer on how far behind it is, rather
than on CPU.

EKS equivalent: KEDA scaling on SQS queue depth or MSK consumer lag, the usual
pattern for queue workers.

## Before you start

On your machine: `kubectl`, `flux`, `k9s`.

In the cluster: the demo running in `otel-demo` (lesson 10).

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `keda` | `infrastructure/base/keda/namespace.yaml` |
| HelmRepository | `keda/kedacore` | `infrastructure/base/keda/source.yaml` |
| HelmRelease | `keda/keda` | `infrastructure/base/keda/release.yaml` |
| ScaledObject | `otel-demo/accounting` | `apps/base/otel-demo/scaledobject.yaml` |

KEDA's defaults are fine, so no values ConfigMaps.

## Tasks

1. HelmRepository `url: https://kedacore.github.io/charts`, HelmRelease
   `keda`, `chart: keda`, `version: 2.21.0`. Push and wait for k9s
   `:helmreleases -n keda` to be `Ready`: the ScaledObject's CRD comes from
   this chart.
2. k9s `:deploy -n otel-demo`: find `accounting` and check how many replicas
   the chart gives it.
3. The ScaledObject. Apply it by hand first, then commit:
   ```yaml
   # apps/base/otel-demo/scaledobject.yaml
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
     triggers:
       - type: kafka
         metadata:
           bootstrapServers: kafka.otel-demo.svc:9092
           consumerGroup: accounting
           topic: orders
           lagThreshold: "10"
   ```
   ```sh
   kubectl --context k3d-dev apply -f apps/base/otel-demo/scaledobject.yaml
   ```
4. k9s `:scaledobjects -n otel-demo` until `READY True`, then `:hpa`: KEDA
   created an HPA for you.
5. Raise the load generator's users at `/loadgen/`, or turn on the
   `kafkaQueueProblems` flag, and watch replicas climb in `:deploy`.
6. Drop the load and watch it scale back after the cooldown.
7. Lag can't be spread over more consumers than the topic has partitions.
   k9s `:pods -n otel-demo`, `s` on the kafka pod:
   ```sh
   # in the pod shell
   kafka-topics.sh --describe --topic orders --bootstrap-server localhost:9092
   ```
   If it isn't on the PATH, `find / -name kafka-topics.sh 2>/dev/null`. See
   what happens to replicas above the partition count.
8. Try `minReplicaCount: 0`, and work out what happens to orders while there
   are no consumers.

## Done when

- You can make the consumer scale out and in on demand, and explain the lag
  numbers KEDA is acting on.

## Where it gets hard

- Flux and KEDA both want to set replicas. If the demo's HelmRelease has drift
  detection on, ignore `/spec/replicas` for Deployments (lesson 9, task 3), or
  they fight.
- Don't add your own HPA for the same Deployment; KEDA owns it.
- Consumers beyond the partition count sit idle.
- The ScaledObject is in `apps-base`, which stops applying until KEDA's CRDs
  exist. Install KEDA first, as in task 1.

## Links

- <https://keda.sh/docs/latest/scalers/apache-kafka/>
- <https://keda.sh/docs/latest/concepts/scaling-deployments/>
- <https://fluxcd.io/flux/components/helm/helmreleases/#drift-detection>
