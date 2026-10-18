# 6. Monitoring

Prometheus and Grafana, plus Cilium and Hubble metrics so you can see the
network layer as graphs as well as flows.

EKS equivalent: the same chart, or Amazon Managed Prometheus and Grafana. The
k3s-specific values are the local ones below.

## Before you start

On your machine: `kubectl`, `flux`, `k9s`, `hubble`.

In the cluster: Flux, with Cilium adopted (end of lesson 2): Cilium's metrics
are switched on through its values. Roughly 2 GB of spare memory.

## Objects

All in namespace `monitoring` unless noted.

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `monitoring` | `infrastructure/base/monitoring/namespace.yaml` |
| HelmRepository | `prometheus-community` | `infrastructure/base/monitoring/source.yaml` |
| HelmRelease | `prometheus-operator-crds` | `infrastructure/base/monitoring/crds.yaml` |
| HelmRelease | `kube-prometheus-stack` | `infrastructure/base/monitoring/release.yaml` |
| ConfigMap | `kube-prometheus-stack-values-base` | `infrastructure/base/monitoring/values.yaml` |
| ConfigMap | `kube-prometheus-stack-values-local` | `infrastructure/local/monitoring/values.yaml` |
| HTTPRoute | `grafana` | `infrastructure/local/monitoring/route.yaml` |
| ConfigMap, changed | `kube-system/cilium-values-base` | `infrastructure/base/cilium/values.yaml` |
| HelmRelease, changed | `kube-system/cilium` | `infrastructure/base/cilium/release.yaml` |

## Tasks

1. The CRDs on their own, so Cilium can depend on them without waiting for the
   whole stack. HelmRepository `url:
   https://prometheus-community.github.io/helm-charts`; HelmRelease
   `prometheus-operator-crds`, `chart: prometheus-operator-crds`,
   `version: 32.0.1`, no values.
2. HelmRelease `kube-prometheus-stack`, `version: 92.10.1`, same source,
   `dependsOn: [{name: prometheus-operator-crds}]`, `valuesFrom` base then
   local.
3. Base values (`kube-prometheus-stack-values-base`):
   ```yaml
   crds:
     enabled: false        # the other release owns them
   prometheus:
     prometheusSpec:
       serviceMonitorSelectorNilUsesHelmValues: false
       podMonitorSelectorNilUsesHelmValues: false
   ```
   The selector settings let Prometheus pick up ServiceMonitors from other
   charts, like Cilium's.
4. Local values (`kube-prometheus-stack-values-local`), because this is k3s:
   ```yaml
   kubeProxy:
     enabled: false        # there's no kube-proxy
   kubeEtcd:
     enabled: false        # k3s runs these in one process bound to localhost,
   kubeControllerManager:  # so their targets would only show as down
     enabled: false
   kubeScheduler:
     enabled: false
   ```
5. Push. k9s `:helmreleases -n monitoring` until both are `Ready`.
6. Grafana: an HTTPRoute `grafana.kube.internal` to Service
   `kube-prometheus-stack-grafana` port 80. The login is in Secret
   `kube-prometheus-stack-grafana`: k9s `:secrets -n monitoring`, `x`.
7. Cilium's metrics. Add to `cilium-values-base` (you'd want these on EKS too):
   ```yaml
   prometheus:
     enabled: true
     serviceMonitor:
       enabled: true
   operator:
     prometheus:
       enabled: true
       serviceMonitor:
         enabled: true
   hubble:
     metrics:
       enabled: [dns, drop, tcp, flow, httpV2]
       serviceMonitor:
         enabled: true
   ```
   Merge these into the existing `hubble:` key rather than adding a second
   one. And in `infrastructure/base/cilium/release.yaml`:
   ```yaml
   spec:
     dependsOn:
       - name: prometheus-operator-crds
         namespace: monitoring
   ```
   Keep `cilium/values.yaml` in step (lesson 2).
8. Prometheus' targets page (k9s `:svc -n monitoring`, `Shift-f` on
   `kube-prometheus-stack-prometheus`, port 9090, then `/targets`): everything
   you enabled is `UP`.
9. Dashboards: the Cilium chart can ship them as ConfigMaps for Grafana's
   sidecar (`dashboards.enabled`, `operator.dashboards.enabled`,
   `hubble.metrics.dashboards.enabled`), or import them by ID from the Cilium
   docs.
10. Generate traffic and find it in the Hubble dashboard: HTTP status codes,
    drops, DNS errors.

## Done when

- A deliberate NetworkPolicy drop shows up in Grafana as well as in
  `hubble observe`.

## Where it gets hard

- Without the selector settings, Prometheus only scrapes ServiceMonitors from
  its own chart, and Cilium's silently go unscraped.
- Cilium's chart refuses to render ServiceMonitors until their CRD exists.
  That's what the `dependsOn` is for.
- HTTP metrics (`httpV2`) only exist for traffic Cilium parses at L7: traffic
  through the Gateway, or pods with an L7 CiliumNetworkPolicy.
- Upgrading `prometheus-operator-crds` across a major version can need manual
  steps; read the chart's upgrade notes first.
- Scraping the k3s control plane needs bind-address flags on the server, which
  is a dotfiles change.

## Links

- <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- <https://docs.cilium.io/en/stable/observability/metrics/>
- <https://docs.cilium.io/en/stable/observability/grafana/>
