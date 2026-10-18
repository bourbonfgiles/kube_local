# 10. OpenTelemetry Demo (microservices)

The OpenTelemetry community's demo shop: about 20 services in a dozen
languages, gRPC and HTTP between them, Kafka for orders, a load generator, a
feature-flag service for injecting faults, and its own Jaeger, Grafana and
Prometheus. One Helm chart.

EKS equivalent: any microservices estate, with X-Ray or a managed tracing
backend in place of the bundled Jaeger.

## Before you start

- Flux, the Gateway, ExternalDNS (lessons 2-3). About 6 GB of free memory.

## Tasks

1. `HelmRepository` `https://open-telemetry.github.io/opentelemetry-helm-charts`,
   chart `opentelemetry-demo`, its own namespace. Defaults first.
2. k9s `:pods -n <ns>` until everything is running. `:xray deploy <ns>` gives
   a feel for the shape.
3. One `HTTPRoute`, `otel.kube.internal`, to Service `frontend-proxy` port
   8080. The proxy serves the shop at `/`, Grafana at `/grafana/`, Jaeger at
   `/jaeger/ui/`, the load generator at `/loadgen/` and the feature flags at
   `/feature/`.
4. Then go round the proxy: a hostname per UI (`grafana.otel.kube.internal`,
   `jaeger.otel.kube.internal`) routed straight to each Service. Find the
   Service names and ports in k9s `:svc`.
5. Follow an order in Jaeger: frontend, checkout, payment, shipping, then the
   Kafka hop to `accounting` and `fraud-detection`.
6. Hubble on the namespace: the same calls seen from the network.
7. Turn on a fault flag in `/feature/` (for example `paymentFailure` or
   `kafkaQueueProblems`), find it in Jaeger and Grafana, turn it off.
8. Lock it down with CiliumNetworkPolicies, one service at a time, using Hubble
   to see what each one needs. Allow the `ingress` entity into the proxy and
   any UIs you routed to directly.
9. Move the values you changed into a local overlay file, as `cilium/` does.

## Done when

- You can take any page load and explain each service it touched, from traces
  and from Hubble.

## Where it gets hard

- Service names depend on the release name. Check `:svc` rather than guessing.
- Grafana and Jaeger expect to be served under the proxy's paths. Routing to
  them directly on their own hostname may need their root-URL settings
  changed in the values.
- It bundles its own Prometheus and Grafana. Once lesson 6 is in, you can turn
  those off and point the collector at yours.
- The Kafka consumers lag when the load generator is busy. Lesson 11 builds on
  that.

## Links

- <https://opentelemetry.io/docs/demo/kubernetes-deployment/>
- <https://opentelemetry.io/docs/demo/architecture/>
- <https://opentelemetry.io/docs/demo/feature-flags/>
