# 11. App: event-driven, built by you

A small system you write yourself: an HTTP producer publishes orders to a
queue, a consumer works through them, and KEDA scales the consumer on queue
lag, down to zero. Writing it is the point: it gives you images for the
registry (step 7) and promotion (step 8).

EKS equivalent: SQS or SNS (or MSK) with KEDA. Locally the broker is NATS
JetStream: official Helm chart, light, and KEDA scales on it directly.

| Broker | Closest AWS service | Local cost |
| --- | --- | --- |
| NATS JetStream (used here) | SQS/SNS-like | Light, Helm chart |
| RabbitMQ (Cluster Operator) | Amazon MQ | Medium, operator manifest |
| Kafka (Strimzi) | MSK | Heavy |

## Before you start

- Steps 2, 7 and 8. `nats` CLI (brew tap `nats-io/nats-tools`).

## Tasks

1. NATS as a HelmRelease: repo `https://nats-io.github.io/k8s/helm/charts/`,
   chart `nats`, with JetStream on and file storage on a PVC.
2. `kubectl port-forward` to 4222, then with the `nats` CLI create a stream
   `ORDERS` on `orders.>` and a durable pull consumer `worker`.
3. Producer, in any language: `POST /orders` publishes to `orders.created`.
   Expose it with an HTTPRoute (`orders.kube.internal`).
4. Consumer: pulls from `worker`, sleeps about a second per message so lag
   builds up, acks.
5. Build both, push as `1.0.0` to the local registry, deploy them from Git.
6. KEDA as a HelmRelease: repo `https://kedacore.github.io/charts`, chart `keda`.
7. `ScaledObject` on the consumer with trigger `nats-jetstream`:
   `natsServerMonitoringEndpoint: nats.<ns>.svc.cluster.local:8222`, `stream:
   ORDERS`, `consumer: worker`, `lagThreshold: "10"`, `minReplicaCount: 0`.
8. Load it (`for i in $(seq 500); do curl -s -XPOST ...; done`) and watch
   `kubectl get hpa,pods -w`: scale up, drain, back to zero.
9. Wire both images into image promotion. Bump the consumer and watch it roll
   while messages are in flight; nothing should be lost.
10. On the host: BCC `tcpconnect` and `tcplife` show the connections to NATS;
    Hubble shows the same from the network side.

## Done when

- Messages survive a consumer restart, scale-to-zero works, and a promotion
  doesn't drop work.

## Where it gets hard

- KEDA reads lag from NATS's monitoring port (8222), not the client port.
  Make sure the chart exposes it.
- Scale-to-zero needs a durable consumer. An ephemeral one disappears with the
  last pod, and KEDA has nothing to measure.
- Ack after processing, not before, or a crash loses the message.
- KEDA creates the HPA. Don't write your own for the same Deployment.

## Links

- <https://keda.sh/docs/latest/scalers/nats-jetstream/>
- <https://docs.nats.io/nats-concepts/jetstream>
- <https://github.com/nats-io/k8s/tree/main/helm/charts/nats>
