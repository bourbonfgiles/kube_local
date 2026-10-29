# 6. Monitoring

> You end up with: Prometheus scraping the cluster, Cilium and Hubble, and
> Grafana at `grafana.kube.internal` with the network as graphs as well as
> flows.

## What it is

**Prometheus** pulls metrics: every scrape interval it fetches `/metrics` from
each target and stores the samples. **Grafana** queries it and draws
dashboards. The **Prometheus Operator** runs Prometheus for you and finds
targets through custom resources, so a chart can ship "scrape me" alongside
its app.

| Kind | Says |
| --- | --- |
| `Prometheus` | Run a Prometheus server, and which monitors and rules to pick up |
| `ServiceMonitor` | Scrape the endpoints behind Services matching these labels, on this port and path |
| `PodMonitor` | The same, selecting pods directly |
| `PrometheusRule` | Recording and alerting rules |

**kube-prometheus-stack** is one chart with the operator, a `Prometheus`,
Alertmanager, Grafana, node-exporter (node metrics) and kube-state-metrics
(object state as metrics), plus dashboards and alerts for all of it.

```mermaid
flowchart LR
  sm["ServiceMonitors<br/>from any chart"] --> op["Prometheus Operator"]
  op -->|"writes scrape config"| prom["Prometheus"]
  prom -->|"scrape /metrics"| t1["cilium-agent :9962"]
  prom --> t2["hubble metrics :9965"]
  prom --> t3["node-exporter, kube-state-metrics,<br/>kubelet, podinfo..."]
  graf["Grafana"] -->|"PromQL"| prom
```

The CRDs come in their own small chart, `prometheus-operator-crds`, so other
charts (Cilium's, for its `ServiceMonitor`s) can depend on them without
waiting for the whole stack.

## On EKS

The same chart, or Amazon Managed Service for Prometheus with Amazon Managed
Grafana, where an in-cluster agent writes to AWS instead of storing locally.
The control-plane targets disabled below exist on EKS only as what AWS
exposes.

## Requirements

**In the cluster**: Flux, with Cilium adopted (end of lesson 2), since
Cilium's metrics are turned on through its values. Roughly 2 GB of spare
memory.

**On your machine**: `kubectl`, `helm`, `flux`, `k9s`, `sofka`, `hubble`.

## Install by hand

### 1. The CRDs, then the stack

```sh
helm --kube-context k3d-dev upgrade --install prometheus-operator-crds prometheus-operator-crds \
  --repo https://prometheus-community.github.io/helm-charts --version 32.0.1 \
  -n monitoring --create-namespace
```

```yaml
# scratch/06/values-base.yaml
crds:
  enabled: false        # the other release owns them
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
```

```yaml
# scratch/06/values-local.yaml
kubeProxy:
  enabled: false        # there's no kube-proxy
kubeEtcd:
  enabled: false        # k3s runs these in one process bound to localhost,
kubeControllerManager:  # so their targets would only ever show as down
  enabled: false
kubeScheduler:
  enabled: false
```

```sh
helm --kube-context k3d-dev upgrade --install kube-prometheus-stack kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version 92.10.1 \
  -n monitoring -f scratch/06/values-base.yaml -f scratch/06/values-local.yaml
```

### 2. Look at it

- Prometheus: k9s `:svc -n monitoring`, `Shift-f` on
  `kube-prometheus-stack-prometheus` port 9090, then <http://localhost:9090/targets>.
- Grafana: `Shift-f` on `kube-prometheus-stack-grafana` port 80. The login is
  in Secret `kube-prometheus-stack-grafana`: `:secrets -n monitoring`, `x`.

### 3. Your own ServiceMonitor

podinfo serves Prometheus metrics on its HTTP port. Scrape it:

```yaml
# scratch/06/podinfo-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: podinfo
  namespace: podinfo
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: podinfo
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

```sh
kubectl --context k3d-dev apply -f scratch/06/podinfo-monitor.yaml
```

Within a minute `podinfo` is on the targets page. In Prometheus, query
`rate(http_requests_total{namespace="podinfo"}[1m])` while you `curl` it.

### 4. Iterate

| Try | Then look at |
| --- | --- |
| Change `matchLabels` to a label podinfo doesn't have | The target disappears; nothing errors |
| Set `serviceMonitorSelectorNilUsesHelmValues: true`, upgrade | Your ServiceMonitor is ignored: Prometheus only picks up the chart's own |
| `interval: 5s` | Smoother graphs, more samples |

**Where to look**

| Check | kubectl | k9s | sofka |
| --- | --- | --- | --- |
| Prometheus | `kubectl --context k3d-dev -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090` | `:svc -n monitoring`, `Shift-f` | `:svc -n monitoring`, `f`, pick 9090 |
| Grafana | `kubectl --context k3d-dev -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` | `Shift-f`, port 80 | `f`, port 80 |
| Grafana's password | `kubectl --context k3d-dev -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` | `:secrets -n monitoring`, `x` | `:secrets -n monitoring`, `x` |
| Forwards running | The terminals running `port-forward` | `:pf` | `:pf` |
| Your ServiceMonitor | `kubectl --context k3d-dev get servicemonitors -A` | `:servicemonitors -A` | `:servicemonitors -A` |
| Releases (Flux part) | `kubectl --context k3d-dev get helmreleases -A` | `:helmreleases -A`, `ctrl-z` | `:helmreleases -A`, `ctrl-z` |

### 5. Clean up

```sh
kubectl --context k3d-dev delete -f scratch/06/podinfo-monitor.yaml
helm --kube-context k3d-dev uninstall kube-prometheus-stack -n monitoring
helm --kube-context k3d-dev uninstall prometheus-operator-crds -n monitoring
```

## Install with Flux

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

1. HelmRepository `url: https://prometheus-community.github.io/helm-charts`.
   Both HelmReleases use it with `chart.spec`, versions as above.
   `kube-prometheus-stack` has `dependsOn: [{name: prometheus-operator-crds}]`
   and `valuesFrom` base then local, holding the two scratch files.
2. Grafana's route: `grafana.kube.internal` to Service
   `kube-prometheus-stack-grafana` port 80.
3. Cilium's metrics. Add to `cilium-values-base`, merging into the existing
   `hubble:` key (you'd want these on EKS too):
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
       enabled:
         - dns
         - drop
         - tcp
         - flow
         - "httpV2:labelsContext=source_namespace,source_workload,destination_namespace,destination_workload"
       serviceMonitor:
         enabled: true
   ```
   `labelsContext` adds who-talked-to-whom labels to the HTTP metrics; lesson
   9's canary checks need them.
   And make Cilium wait for the CRDs, in its `release.yaml`:
   ```yaml
   spec:
     dependsOn:
       - name: prometheus-operator-crds
         namespace: monitoring
   ```
   Keep `cilium/values.yaml` matching (lesson 2).
4. Push. The targets page now lists `cilium-agent`, `cilium-operator` and
   `hubble`, all `UP`.

## Exercises

1. Find node CPU in Grafana's "Node Exporter / Nodes" dashboard, then the same
   number with PromQL.
2. Dashboards for Cilium: the chart can ship them as ConfigMaps for Grafana's
   sidecar (`dashboards.enabled`, `operator.dashboards.enabled`,
   `hubble.metrics.dashboards.enabled`), or import them by ID from the Cilium
   docs.
3. Generate traffic through the Gateway and find it in the Hubble dashboard:
   status codes, latency.
4. Harder: drop traffic on purpose with a NetworkPolicy and find the same drop
   in `hubble observe`, in `hubble_drop_total` and in Grafana.

## Where it gets hard

- Without the selector settings, Prometheus only scrapes the chart's own
  ServiceMonitors, and every other chart's are silently ignored.
- Cilium's chart refuses to render ServiceMonitors until their CRD exists.
  That's what its `dependsOn` is for. sofka's `:gitops` on the `cilium`
  HelmRelease shows the edge and whether it's met.
- HTTP metrics (`httpV2`) only exist for traffic Cilium parses at L7: traffic
  through the Gateway, or pods with an L7 CiliumNetworkPolicy.
- Upgrading `prometheus-operator-crds` across a major version can need manual
  steps; read the chart's upgrade notes first.
- Scraping the k3s control plane needs bind-address flags on the server, which
  is a dotfiles change.

## Links

- <https://prometheus-operator.dev/docs/developer/getting-started/>
- <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- <https://docs.cilium.io/en/stable/observability/metrics/>
