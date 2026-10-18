# 1. Cilium and Gateway API by hand

Learn Gateway API and Hubble with `kubectl` before GitOps hides the moving
parts. Everything here gets deleted at the end; Flux recreates it in step 2.

EKS equivalent: Cilium as the CNI on EKS, or the AWS Load Balancer Controller
reading Gateway API objects.

## Before you start

- `cilium status --context k3d-dev` is all green.
- `kubectl get gatewayclass` shows `cilium` `ACCEPTED True`.

## Tasks

1. Look around: `cilium config view | grep -iE 'gateway|kube-proxy|l2'` and
   `kubectl -n kube-system exec ds/cilium -- cilium-dbg service list`. That
   table is what kube-proxy would otherwise do in iptables.
2. Start Hubble: `cilium hubble port-forward &`, then `hubble observe -f` in a
   spare terminal. `cilium hubble ui` for the graph.
3. Two test apps in a namespace `demo`: Deployments `blue` and `green` from
   `ghcr.io/stefanprodan/podinfo:6.7.1` with `PODINFO_UI_MESSAGE` set to tell
   them apart, each with a ClusterIP Service on port 9898.
4. A `Gateway` named `web` in namespace `gateway`: class `cilium`, one HTTP
   listener on 80, `allowedRoutes.namespaces.from: All`.
5. `kubectl get gateway -n gateway` until `PROGRAMMED True` with an address
   (usually `10.89.0.200`). Note the `cilium-gateway-web` LoadBalancer Service
   Cilium created for it.
6. An `HTTPRoute` in `demo`, hostname `demo.kube.internal`, `/` to `blue`.
   `curl -H 'Host: demo.kube.internal' http://10.89.0.200/`.
7. Add rules: `/green` to `green` (with a `URLRewrite` filter so podinfo sees
   `/`), a header match `x-colour: green` to `green`, then a 90/10 weighted
   split between the two.
8. Watch the requests in Hubble. The source is `(ingress)`, Cilium's Envoy.
9. Clean up: delete `demo` and the `gateway` namespace.

## Done when

- You can predict which backend a request hits from its path and headers.
- `kubectl describe httproute` shows `Accepted` and `ResolvedRefs` true, and
  you know what each means.

## Where it gets hard

- A route that doesn't attach shows nothing in `curl`; the reason is in the
  route's `status.parents`. Usual causes: wrong Gateway namespace in
  `parentRefs`, or the listener's `allowedRoutes` excluding the route's
  namespace.
- A `ReferenceGrant` is needed when a route points at a Service in another
  namespace.
- `curl` without the `Host` header gets a 404 from Envoy: no route matches.

## Links

- <https://gateway-api.sigs.k8s.io/guides/http-routing/>
- <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
- <https://docs.cilium.io/en/stable/observability/hubble/>
