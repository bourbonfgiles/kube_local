# 9. Progressive delivery with Flagger

Flagger is Flux's progressive delivery tool. When a Deployment changes, it
shifts traffic to the new version step by step by rewriting an `HTTPRoute`'s
weights, checks metrics at each step, and rolls back if they go bad. Combined
with lesson 8, a mirrored tag becomes a canary release with no hands involved.

EKS equivalent: the same, against whatever implements Gateway API there
(Cilium, or the AWS Load Balancer Controller).

## Before you start

On your machine: `kubectl`, `flux`, `skopeo`, `k9s`.

In the cluster: the Gateway in Git (lesson 2), monitoring with Hubble
`httpV2` metrics (lesson 6), and podinfo with two mirrored tags (lesson 7).

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `flagger-system` | `infrastructure/base/flagger/namespace.yaml` |
| HelmRepository | `flagger-system/flagger` | `infrastructure/base/flagger/source.yaml` |
| HelmRelease | `flagger-system/flagger` | `infrastructure/base/flagger/release.yaml` |
| ConfigMap | `flagger-system/flagger-values-base` | `infrastructure/base/flagger/values.yaml` |
| HelmRelease | `podinfo/loadtester` | `apps/base/podinfo/loadtester.yaml` |
| Canary | `podinfo/podinfo` | `apps/local/podinfo/canary.yaml` (names the local host) |
| MetricTemplate | `podinfo/error-rate` | `apps/base/podinfo/metric-template.yaml` |
| HTTPRoute, deleted | `podinfo/podinfo` | `apps/local/podinfo/route.yaml`: Flagger makes its own |
| ConfigMap, changed | `podinfo/podinfo-values-base` | `apps/base/podinfo/values.yaml` |
| HelmRelease, changed | `podinfo/podinfo` | `apps/base/podinfo/release.yaml` |

## Tasks

1. Flagger: HelmRepository `url: https://flagger.app`, HelmRelease `flagger`,
   `chart: flagger`, `version: 1.45.0`. Base values:
   ```yaml
   meshProvider: gatewayapi:v1
   prometheus:
     install: false
   metricsServer: http://kube-prometheus-stack-prometheus.monitoring:9090
   ```
2. HelmRelease `loadtester` in `podinfo`, `chart: loadtester`,
   `version: 0.39.0`, with `sourceRef` naming the HelmRepository in
   `flagger-system` (`namespace: flagger-system`). It generates traffic during
   analysis.
3. podinfo hands its Service and route to Flagger. In `podinfo-values-base`:
   ```yaml
   service:
     enabled: false        # Flagger creates podinfo, -primary and -canary
   ```
   Delete `apps/local/podinfo/route.yaml`. If podinfo's HelmRelease has
   `driftDetection` on, stop it fighting Flagger over replicas:
   ```yaml
   spec:
     driftDetection:
       mode: enabled
       ignore:
         - paths: ["/spec/replicas"]
           target:
             kind: Deployment
   ```
4. The Canary. Apply it by hand first, then commit:
   ```yaml
   # apps/local/podinfo/canary.yaml
   apiVersion: flagger.app/v1beta1
   kind: Canary
   metadata:
     name: podinfo
     namespace: podinfo
   spec:
     targetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: podinfo
     service:
       port: 9898
       hosts: [podinfo.kube.internal]
       gatewayRefs:
         - name: web
           namespace: gateway
     analysis:
       interval: 30s
       threshold: 3
       stepWeight: 10
       maxWeight: 50
       webhooks:
         - name: load
           url: http://loadtester.podinfo/
           metadata:
             cmd: "hey -z 1m -q 10 -c 2 http://podinfo-canary.podinfo:9898/"
   ```
   The loadtester's Service is named after its release; check `:svc -n
   podinfo` if the URL doesn't answer.
5. k9s `:canaries -n podinfo` until `Initialized`. `:deploy` now shows
   `podinfo-primary`; `:httproutes` shows the one Flagger owns.
6. Release: mirror a new tag (lesson 8 commits it), or bump the tag in Git
   yourself. Watch the weights move (`d` on the route) and `:canaries`
   progress to `Succeeded`.
7. Measure something: a `MetricTemplate` querying the error rate from
   Hubble's `hubble_http_requests_total`, referenced in `analysis.metrics`
   with a `thresholdRange`.
8. Fail one on purpose: set `faults.error: true` in podinfo's values, push it
   as a "release", and watch the rollback.

## Done when

- A good release promotes itself; a bad one rolls back with the reason in the
  Canary's events (`d` in k9s) and `flux --context k3d-dev events -n podinfo`.

## Where it gets hard

- Flagger takes over the Deployment: traffic goes to `podinfo-primary`, and the
  Deployment you manage is scaled to zero between releases. Expect that in
  k9s.
- Flagger's example metric queries are written for Envoy in Istio. With Cilium
  you write your own against Hubble's metrics, so get lesson 6 solid first.
- Without traffic there's nothing to measure, and analysis fails. That's why
  the loadtester is there.
- With `faults.error` in a values ConfigMap, the rollback reverts the
  Deployment but Git still says broken. Revert the commit too.
- ExternalDNS sees Flagger's route like any other; the hostname stays the
  same.

## Links

- <https://docs.flagger.app/tutorials/gatewayapi-progressive-delivery>
- <https://docs.flagger.app/usage/metrics>
- <https://docs.cilium.io/en/stable/observability/metrics/>
