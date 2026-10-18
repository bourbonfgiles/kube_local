# 9. Progressive delivery with Flagger

Flagger is Flux's progressive delivery tool. When a Deployment changes, it
shifts traffic to the new version step by step by rewriting an `HTTPRoute`'s
weights, checks metrics at each step, and rolls back if they go bad. Combined
with lesson 8, a mirrored tag becomes a canary release with no hands involved.

EKS equivalent: the same, against the AWS Load Balancer Controller's Gateway
API or App Mesh. Argo Rollouts is the Argo-world equivalent.

## Before you start

- The Gateway in Git (lesson 2), monitoring with Hubble `httpV2` metrics
  (lesson 6), and podinfo with two mirrored tags (lesson 7).

## Tasks

1. `HelmRepository` `https://flagger.app`; HelmRelease `flagger` in
   `flagger-system` with `meshProvider: gatewayapi:v1`, `prometheus.install:
   false`, and `metricsServer` pointing at your Prometheus.
2. HelmRelease `loadtester` from the same repo, in podinfo's namespace. It
   generates traffic during analysis.
3. Remove podinfo's own `HTTPRoute`; Flagger generates one.
4. A `Canary` for podinfo: `targetRef` the Deployment, `service.port: 9898`,
   `service.gatewayRefs` your Gateway, `service.hosts` its hostname.
5. `analysis`: `interval: 30s`, `threshold: 3`, `stepWeight: 10`, `maxWeight:
   50`, and a webhook that has the loadtester `hey` the canary. No metrics yet.
6. k9s `:canaries` until `Initialized`. `:deploy` now shows `podinfo-primary`;
   `:httproutes` shows the one Flagger owns.
7. Bump the tag in Git, or let lesson 8 do it. Watch the route weights move
   in k9s (`d` on the route) and `:canaries` progress to `Succeeded`.
8. Add a `MetricTemplate` for the error rate from Hubble's
   `hubble_http_requests_total`, and reference it in `analysis.metrics`.
9. Fail one on purpose: podinfo's chart can make the pod return errors
   (`faults.error` in its values). Ship that as a "release" and watch the
   rollback.

## Done when

- A good release promotes itself; a bad one rolls back with the reason in
  `flux events` and the Canary's events.

## Where it gets hard

- Flagger takes over the Deployment: traffic goes to `podinfo-primary`, and the
  Deployment you manage is scaled to zero between releases. Expect that in
  k9s.
- Flagger's example metric queries are written for Envoy in Istio. With Cilium
  you write your own against Hubble's metrics, so get lesson 6 solid first.
- Without traffic there's nothing to measure, and analysis fails. That's why
  the loadtester is there.
- ExternalDNS sees Flagger's routes like any other; the hostname stays the
  same.

## Links

- <https://docs.flagger.app/tutorials/gatewayapi-progressive-delivery>
- <https://docs.flagger.app/usage/metrics>
- <https://docs.cilium.io/en/stable/observability/metrics/>
