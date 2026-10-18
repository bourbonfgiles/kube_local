# 10. App: Bookinfo (microservices, many routes)

Istio's Bookinfo: four services in four languages (productpage, details,
reviews with three versions, ratings). Each one speaks plain HTTP, so you can
route to each directly, and the three `reviews` versions make weighted and
header-based routing visible in the page. Cilium's own Gateway API examples use
it.

## Before you start

- The Gateway in Git (step 2), names (step 3). HTTPS (step 4) is optional.

## Tasks

1. Pick an Istio release tag and copy `samples/bookinfo/platform/kube/bookinfo.yaml`
   and `bookinfo-versions.yaml` into `apps/bookinfo/`. They're plain manifests
   with no chart, so note the tag you took them from.
2. A Flux `Kustomization` for `./apps/bookinfo`, `dependsOn` the infrastructure
   one, `targetNamespace: bookinfo`.
3. HTTPRoute `bookinfo.kube.internal`: `/` and `/static` to `productpage:9080`.
4. More rules on the same hostname: `/details` to `details`, `/reviews` to
   `reviews`, `/ratings` to `ratings`. Try `curl .../details/0`.
5. Weighted: send `/reviews` 80/20 to `reviews-v1` and `reviews-v3` (the
   per-version Services come from `bookinfo-versions.yaml`).
6. Header match: `end-user: jason` goes to `reviews-v2`.
7. Separate hostnames per service instead of paths (`details.bookinfo.kube.internal`),
   and compare.
8. Lock it down: CiliumNetworkPolicies so only productpage can call details
   and reviews, and only reviews can call ratings. Allow the `ingress` entity
   into productpage.
9. `hubble observe -n bookinfo --verdict DROPPED` while you try a forbidden
   call.

## Done when

- You can change who sees which reviews version from Git alone, and Hubble
  shows only the calls your policy allows.

## Where it gets hard

- The weighted and header rules only apply to requests through the Gateway.
  When productpage calls `reviews` inside the cluster, it uses the `reviews`
  Service directly, so the page still shows a random version. Routing
  in-cluster traffic needs routes attached to a Service (GAMMA); check
  Cilium's support before relying on it.
- Paths are passed through as-is; use a `URLRewrite` filter if a service
  doesn't expect the prefix.
- Once policies are on, the Gateway needs `fromEntities: [ingress]`, or you get
  503s with no Hubble drop.

## Links

- <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/http/>
- <https://istio.io/latest/docs/examples/bookinfo/>
- <https://gateway-api.sigs.k8s.io/guides/traffic-splitting/>
