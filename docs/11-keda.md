# 11. Event-driven scaling with KEDA

The OpenTelemetry Demo is event-driven inside: checkout publishes orders to
the Kafka topic `orders`, and the `accounting` service reads them as consumer
group `accounting`. KEDA scales that consumer on how far behind it is, rather
than on CPU.

EKS equivalent: KEDA scaling on SQS queue depth or MSK consumer lag, the usual
pattern for queue workers.

## Before you start

- The demo running (lesson 10).

## Tasks

1. `HelmRepository` `https://kedacore.github.io/charts`, HelmRelease `keda` in
   namespace `keda`.
2. k9s `:deploy -n <demo ns>`: find the accounting Deployment and check how many
   replicas the chart gives it.
3. A `ScaledObject` targeting it, trigger type `kafka`:
   `bootstrapServers: kafka.<ns>.svc:9092`, `consumerGroup: accounting`,
   `topic: orders`, `lagThreshold: "10"`, `minReplicaCount: 1`,
   `maxReplicaCount: 3`.
4. k9s `:scaledobjects` until ready, then `:hpa`: KEDA created an HPA for you.
5. Raise the load generator's users at `/loadgen/`, or turn on the
   `kafkaQueueProblems` flag, and watch replicas climb in `:deploy`.
6. Drop the load and watch it scale back after the cooldown.
7. Lag can't be spread over more consumers than the topic has partitions. Find
   the partition count and see what happens to replicas above it.
8. Try `minReplicaCount: 0`, and work out what happens to orders while there
   are no consumers.

## Done when

- You can make the consumer scale out and in on demand, and explain the lag
  numbers KEDA is acting on.

## Where it gets hard

- Flux and KEDA both want to set replicas. If the HelmRelease enforces
  replicas (drift detection), ignore `/spec/replicas` for that Deployment, or
  they fight.
- Don't add your own HPA for the same Deployment; KEDA owns it.
- Consumers beyond the partition count sit idle.
- The Service and Deployment names come from the demo's release name. Check in
  k9s.

## Links

- <https://keda.sh/docs/latest/scalers/apache-kafka/>
- <https://keda.sh/docs/latest/concepts/scaling-deployments/>
- <https://fluxcd.io/flux/components/helm/helmreleases/#drift-detection>
