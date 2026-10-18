# 6. Monitoring

Prometheus and Grafana, plus Cilium and Hubble metrics so you can see the
network layer as graphs as well as flows.

EKS equivalent: the same chart, or Amazon Managed Prometheus and Grafana.

## Before you start

- Flux, with Cilium adopted (end of step 2): Cilium's metrics are switched on
  through its values.
- Roughly 2 GB of spare memory.

## Tasks

1. `HelmRepository` `https://prometheus-community.github.io/helm-charts`, chart
   `kube-prometheus-stack`, namespace `monitoring`.
2. k3s values:
   - `kubeProxy.enabled: false`: there's no kube-proxy.
   - `kubeEtcd`, `kubeControllerManager`, `kubeScheduler` disabled for now.
     k3s runs them inside one process bound to localhost, so their targets
     show as down.
   - `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false`
     (and the same for `podMonitorSelector...`), so Prometheus picks up
     ServiceMonitors from other charts.
3. An `HTTPRoute` for Grafana at `grafana.kube.internal`. The admin password is
   in a Secret the chart creates.
4. In the Cilium HelmRelease: `prometheus.enabled`, `operator.prometheus.enabled`,
   `hubble.metrics.enabled: [dns, drop, tcp, flow, httpV2]`, each with
   `serviceMonitor.enabled: true`.
5. `dependsOn` from Cilium to the monitoring HelmRelease, so the ServiceMonitor
   CRD exists first.
6. Prometheus targets page: everything you enabled is `UP`.
7. Import the Cilium, Cilium operator and Hubble dashboards (IDs are in the
   Cilium docs).
8. Generate traffic and find it in the Hubble dashboard: HTTP status codes,
   drops, DNS errors.

## Done when

- A deliberate NetworkPolicy drop shows up in Grafana as well as in
  `hubble observe`.

## Where it gets hard

- Without the selector setting, Prometheus only scrapes ServiceMonitors from
  its own chart, and Cilium's silently go unscraped.
- HTTP metrics (`httpV2`) only exist for traffic Cilium parses at L7: traffic
  through the Gateway, or pods with an L7 CiliumNetworkPolicy.
- The chart's CRDs are large and upgrade separately from the chart. Read the
  upgrade notes before bumping a major version.
- Scraping the k3s control plane needs bind-address flags on the server, which
  is a dotfiles change.

## Links

- <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- <https://docs.cilium.io/en/stable/observability/metrics/>
- <https://docs.cilium.io/en/stable/observability/grafana/>
