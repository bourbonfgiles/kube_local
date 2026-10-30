# 10. OpenTelemetry Demo (microservices)

> You end up with: a 20-service shop at `otel.kube.internal`, every request
> traceable from the browser through gRPC calls and a Kafka hop, and the same
> calls visible in Hubble.

## What it is

The OpenTelemetry community's demo shop. It exists to show a realistic
microservices estate with telemetry everywhere, so it's ideal to deploy and
take apart. One Helm chart installs:

| Part | What |
| --- | --- |
| Services | About 20, in a dozen languages: frontend, cart, checkout, payment, shipping, currency, recommendation, ad, email, quote, accounting, fraud-detection... |
| Protocols | HTTP and gRPC between services; Kafka topic `orders` from checkout to `accounting` and `fraud-detection` |
| `frontend-proxy` | Envoy in front of everything on port 8080, serving the shop and every UI under one hostname |
| `load-generator` | Locust, simulating shoppers |
| `flagd` | Feature flags that inject faults on demand |
| Telemetry | An OpenTelemetry Collector receiving traces, metrics and logs, with bundled Jaeger, Prometheus, Grafana and OpenSearch |

```mermaid
flowchart LR
  you["Browser"] --> gw["Gateway web"] --> proxy["frontend-proxy :8080"]
  proxy --> fe["frontend"]
  proxy -->|"/jaeger/ui/ /grafana/<br/>/loadgen/ /feature/"| uis["UIs"]
  fe --> cart & checkout & rec["recommendation"] & ad
  checkout --> payment & shipping & currency & email
  checkout -->|"Kafka: orders"| kafka["kafka"]
  kafka --> accounting & fraud["fraud-detection"]
  fe & checkout & payment -.->|"OTLP"| col["otel-collector"]
  col -.-> jaeger & prom["prometheus"]
```

Every service sends **traces** to the collector over OTLP. A trace follows one
request across every service it touches; each hop is a span. That's what
makes this the right thing to learn microservices on: you can see them.

## On EKS

Any microservices estate, with the collector sending to AWS X-Ray, Amazon
Managed Prometheus or a vendor backend instead of the bundled Jaeger and
Prometheus.

## Requirements

**In the cluster**: Flux, the Gateway and ExternalDNS (lessons 2-3). About 6 GB
of free memory.

**On your machine**: `kubectl`, `helm`, `flux`, `hubble`, `curl`, and `sofka` or `k9s`
([lesson 0](00-tools.md)).

## Install by hand

### 1. Defaults first

```sh
helm --kube-context k3d-dev upgrade --install otel-demo opentelemetry-demo \
  --repo https://open-telemetry.github.io/opentelemetry-helm-charts --version 0.42.4 \
  -n otel-demo --create-namespace
```

```sh
kubectl --context k3d-dev get pods -n otel-demo -w
kubectl --context k3d-dev get deploy,sts,jobs,svc -n otel-demo
```

Wait until everything is running (a few minutes; Kafka is slowest). The
second command is the shape: every workload, and the Services between them.
A `Pending` pod says why in
`kubectl --context k3d-dev get events -n otel-demo --field-selector reason=FailedScheduling`.

sofka / k9s: `:pods -n otel-demo`, `ctrl-z` for stragglers, `d` on one. They
differ on the shape:

- sofka: `:workloads otel-demo` for every workload in one list; `:xray` from
  `:deploy -n otel-demo`. `X` on a `Pending` pod ([lesson 0](00-tools.md)).
- k9s: `:xray deploy otel-demo`.

### 2. A route to the proxy

**`scratch/10/route.yaml`**
```yaml
# scratch/10/route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: otel
  namespace: otel-demo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames: [otel.kube.internal]
  rules:
    - backendRefs:
        - name: frontend-proxy
          port: 8080
```

```sh
kubectl --context k3d-dev apply -f scratch/10/route.yaml
```

ExternalDNS names it. Open `http(s)://otel.kube.internal/` for the shop, and
`/jaeger/ui/`, `/grafana/`, `/loadgen/`, `/feature/` for the rest.

### 3. Iterate

| Try | Then look at |
| --- | --- |
| In Jaeger, pick service `frontend`, find a `checkout` trace | Every span, including the Kafka hop to `accounting` |
| Turn on `paymentFailure` in `/feature/` | Red spans in Jaeger, errors in Grafana. Turn it off again there. |

The same calls from the network's side, with Hubble's port-forward running in
another terminal:

```sh
cilium --context k3d-dev hubble port-forward     # terminal 1, leave running
hubble observe -n otel-demo -f                    # terminal 2
```

`paymentFailure` from the inside:

```sh
kubectl --context k3d-dev -n otel-demo logs deploy/payment -f
```

sofka / k9s: `l` on `payment`. sofka extra: in the logs view, `J` cycles the
JSON lines through raw, record and pretty, and `ctrl-z` leaves only the errors.

New or changed lines sit between `# ── new ──` and `# ── end new ──`.

<details>
<summary>1. Jaeger on its own hostname</summary>

Jaeger's Service is `jaeger`, port `16686`, and it serves under
`/jaeger/ui` because the chart sets that base path for the proxy. A second
route in the same file:

**`scratch/10/route.yaml`**
```yaml
# scratch/10/route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: otel
  namespace: otel-demo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames: [otel.kube.internal]
  rules:
    - backendRefs:
        - name: frontend-proxy
          port: 8080
# ── new ──
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: jaeger
  namespace: otel-demo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames: [jaeger.otel.kube.internal]
  rules:
    - backendRefs:
        - name: jaeger
          port: 16686
# ── end new ──
```

```sh
kubectl --context k3d-dev apply -f scratch/10/route.yaml
kubectl --context k3d-dev get svc jaeger -n otel-demo
curl -s -o /dev/null -w '%{http_code}\n' http://jaeger.otel.kube.internal/jaeger/ui/
```

`200` once ExternalDNS has the name. `/` on its own 404s: the base path stays
`/jaeger/ui` unless you change it in values.

</details>

<details>
<summary>2. More load</summary>

**`scratch/10/load.yaml`**
```yaml
# scratch/10/load.yaml
components:
  load-generator:
    envOverrides:
      - name: LOCUST_USERS
        value: "50"
```

```sh
helm --kube-context k3d-dev upgrade --install otel-demo opentelemetry-demo \
  --repo https://open-telemetry.github.io/opentelemetry-helm-charts --version 0.42.4 \
  -n otel-demo -f scratch/10/load.yaml
kubectl --context k3d-dev -n otel-demo set env deploy/load-generator --list | grep LOCUST_USERS
```

`LOCUST_USERS=50`, and more traffic everywhere. Back to the chart's 5:

```sh
helm --kube-context k3d-dev upgrade --install otel-demo opentelemetry-demo \
  --repo https://open-telemetry.github.io/opentelemetry-helm-charts --version 0.42.4 \
  -n otel-demo
kubectl --context k3d-dev -n otel-demo set env deploy/load-generator --list | grep LOCUST_USERS
```

</details>

### 4. Clean up

```sh
kubectl --context k3d-dev delete -f scratch/10/route.yaml
helm --kube-context k3d-dev uninstall otel-demo -n otel-demo
kubectl --context k3d-dev delete namespace otel-demo
```

## Install with Flux

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `otel-demo` | `apps/base/otel-demo/namespace.yaml` |
| HelmRepository | `open-telemetry` | `apps/base/otel-demo/source.yaml` |
| HelmRelease | `otel-demo` | `apps/base/otel-demo/release.yaml` |
| ConfigMap | `otel-demo-values-base` | `apps/base/otel-demo/values.yaml` |
| ConfigMap | `otel-demo-values-local` | `apps/local/otel-demo/values.yaml` |
| HTTPRoute | `otel` | `apps/local/otel-demo/route.yaml` |

Values you'd keep anywhere (components off, resources) go in base; hostnames
and root URLs in local. Both start empty.

<details>
<summary>The demo as Flux files</summary>

**`apps/base/otel-demo/namespace.yaml`**
```yaml
# apps/base/otel-demo/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: otel-demo
```

**`apps/base/otel-demo/source.yaml`**
```yaml
# apps/base/otel-demo/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: open-telemetry
  namespace: otel-demo
spec:
  interval: 1h
  url: https://open-telemetry.github.io/opentelemetry-helm-charts
```

**`apps/base/otel-demo/release.yaml`**
```yaml
# apps/base/otel-demo/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: otel-demo
  namespace: otel-demo
spec:
  interval: 10m
  chart:
    spec:
      chart: opentelemetry-demo
      version: 0.42.4
      sourceRef:
        kind: HelmRepository
        name: open-telemetry
  valuesFrom:
    - kind: ConfigMap
      name: otel-demo-values-base
    - kind: ConfigMap
      name: otel-demo-values-local
```

**`apps/base/otel-demo/values.yaml`**
```yaml
# apps/base/otel-demo/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-demo-values-base
  namespace: otel-demo
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: "{}"
```

**`apps/local/otel-demo/values.yaml`**
```yaml
# apps/local/otel-demo/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-demo-values-local
  namespace: otel-demo
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: "{}"
```

**`apps/local/otel-demo/route.yaml`**
```yaml
# apps/local/otel-demo/route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: otel
  namespace: otel-demo
spec:
  parentRefs:
    - name: web
      namespace: gateway
  hostnames: [otel.kube.internal]
  rules:
    - backendRefs:
        - name: frontend-proxy
          port: 8080
```

</details>

## Exercises

1. Take one page load and explain every service it touched, from the trace
   and from Hubble.
2. Turn on `kafkaQueueProblems` and find the lag in Grafana. Lesson 11 builds
   on this.
3. Once lesson 6 is in: turn off the bundled Prometheus and Grafana in base
   values and point the collector at yours.
4. Harder: lock the namespace down with CiliumNetworkPolicies, one service at a
   time, using Hubble to see what each one needs. Allow the `ingress` entity
   into `frontend-proxy`. Finish with a default-deny that the shop still works
   behind.

## Where it gets hard

- Check Service names with `get svc` rather than guessing; some depend on the
  release name.
- Grafana and Jaeger expect to be served under the proxy's paths. On their own
  hostname they may need root-URL settings in the values.
- Memory: OpenSearch and Kafka are the heavy ones. If pods are `Pending`, check
  `kubectl --context k3d-dev top nodes`. That's usage, but the scheduler places
  pods by requests: sofka's `:nodes` ([lesson 0](00-tools.md)) has `%CPU/R` and `%MEM/R`, the share of
  each node that pods have already asked for.
- The Kafka consumers lag when the load generator is busy. That's lesson 11.

## Links

- <https://opentelemetry.io/docs/demo/architecture/>
- <https://opentelemetry.io/docs/demo/kubernetes-deployment/>
- <https://opentelemetry.io/docs/demo/feature-flags/>
