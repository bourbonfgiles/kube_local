# 10. OpenTelemetry Demo (microservices)

The OpenTelemetry community's demo shop: about 20 services in a dozen
languages, gRPC and HTTP between them, Kafka for orders, a load generator, a
feature-flag service for injecting faults, and its own Jaeger, Grafana and
Prometheus. One Helm chart.

EKS equivalent: any microservices estate, with X-Ray or a managed tracing
backend in place of the bundled Jaeger.

## Before you start

On your machine: `kubectl`, `flux`, `hubble`, `curl`, `k9s`.

In the cluster: Flux, the Gateway and ExternalDNS (lessons 2-3). About 6 GB of
free memory.

## Objects

All in namespace `otel-demo`.

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `otel-demo` | `apps/base/otel-demo/namespace.yaml` |
| HelmRepository | `open-telemetry` | `apps/base/otel-demo/source.yaml` |
| HelmRelease | `otel-demo` | `apps/base/otel-demo/release.yaml` |
| ConfigMap | `otel-demo-values-base` | `apps/base/otel-demo/values.yaml` |
| ConfigMap | `otel-demo-values-local` | `apps/local/otel-demo/values.yaml` |
| HTTPRoute | `otel`, `grafana`, `jaeger` | `apps/local/otel-demo/routes.yaml` |
| CiliumNetworkPolicy | one per service | `apps/base/otel-demo/policies.yaml` |

## Tasks

1. HelmRepository `url:
   https://open-telemetry.github.io/opentelemetry-helm-charts`, HelmRelease
   `otel-demo`, `chart: opentelemetry-demo`, `version: 0.42.4`. Both values
   ConfigMaps start as `values.yaml: "{}"`: defaults first.
2. k9s `:pods -n otel-demo` until everything is running. `:xray deploy
   otel-demo` gives a feel for the shape.
3. One HTTPRoute, `otel.kube.internal`, to Service `frontend-proxy` port
   8080. The proxy serves the shop at `/`, Grafana at `/grafana/`, Jaeger at
   `/jaeger/ui/`, the load generator at `/loadgen/` and the feature flags at
   `/feature/`.
4. Then go round the proxy: a hostname per UI (`grafana.otel.kube.internal`,
   `jaeger.otel.kube.internal`) routed straight to each Service. Find their
   names and ports in k9s `:svc -n otel-demo`.
5. Follow an order in Jaeger: frontend, checkout, payment, shipping, then the
   Kafka hop to `accounting` and `fraud-detection`.
6. Hubble on the namespace: the same calls seen from the network.
   ```sh
   hubble observe -n otel-demo -f
   ```
   (with `cilium --context k3d-dev hubble port-forward` running).
7. Turn on a fault flag in `/feature/` (for example `paymentFailure` or
   `kafkaQueueProblems`), find it in Jaeger and Grafana, turn it off.
8. Lock it down with CiliumNetworkPolicies, one service at a time, using Hubble
   to see what each one needs. Apply each by hand while you work it out, then
   commit. Allow the `ingress` entity into `frontend-proxy` and any UI you
   routed to directly.
9. Any values you changed go into the ConfigMaps: settings you'd keep on EKS
   (turning components off, resources) in base, hostnames and root URLs in
   local.

## Done when

- You can take any page load and explain each service it touched, from traces
  and from Hubble.

## Where it gets hard

- Check Service names in `:svc` rather than guessing; some depend on the
  release name.
- Grafana and Jaeger expect to be served under the proxy's paths. Routing to
  them directly on their own hostname may need their root-URL settings
  changed in the local values.
- It bundles its own Prometheus and Grafana. Once lesson 6 is in, you can turn
  those off in base values and point the collector at yours.
- The Kafka consumers lag when the load generator is busy. Lesson 11 builds on
  that.

## Links

- <https://opentelemetry.io/docs/demo/kubernetes-deployment/>
- <https://opentelemetry.io/docs/demo/architecture/>
- <https://opentelemetry.io/docs/demo/feature-flags/>
