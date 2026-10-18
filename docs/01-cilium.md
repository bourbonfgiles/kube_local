# 1. Cilium and Gateway API by hand

Learn Gateway API and Hubble with `helm` and `kubectl` before GitOps hides the
moving parts. Everything here gets deleted at the end; Flux recreates it in
lesson 2.

EKS equivalent: Cilium as the CNI on EKS, or the AWS Load Balancer Controller
reading Gateway API objects.

## Before you start

- `cilium status --context k3d-dev` is all green.
- k9s `:gatewayclasses` shows `cilium` accepted.

## Tasks

1. Look around: `cilium config view | grep -iE 'gateway|kube-proxy|l2'`. In k9s,
   `:pods -n kube-system`, pick a `cilium-` pod, `s` for a shell, and run
   `cilium-dbg service list`. That table is what kube-proxy would otherwise do in
   iptables.
2. Hubble: `cilium hubble port-forward &`, then `hubble observe -f` in a spare
   terminal. `cilium hubble ui` for the graph.
3. Two podinfo releases in namespace `demo`, so you have two backends to route
   between:
   ```sh
   helm install blue  oci://ghcr.io/stefanprodan/charts/podinfo -n demo --create-namespace --set ui.message=blue
   helm install green oci://ghcr.io/stefanprodan/charts/podinfo -n demo --set ui.message=green
   ```
4. A `Gateway` named `web` in namespace `gateway`: class `cilium`, one HTTP
   listener on 80, `allowedRoutes.namespaces.from: All`.
5. k9s `:gateways` until it's programmed with an address (usually
   `10.89.0.200`). `:svc -n gateway` shows the LoadBalancer Service Cilium
   made for it.
6. An `HTTPRoute` in `demo`: hostname `demo.kube.internal`, `/` to
   `blue-podinfo:9898`.
   `curl -H 'Host: demo.kube.internal' http://10.89.0.200/`.
7. Add rules: `/green` to `green-podinfo` (with a `URLRewrite` filter so
   podinfo sees `/`), a header match `x-colour: green`, then a 90/10 weighted
   split.
8. Watch the requests in Hubble. The source is `(ingress)`, Cilium's Envoy.
9. Clean up: `helm uninstall` both, delete the `demo` and `gateway` namespaces.

## Done when

- You can predict which backend a request hits from its path and headers.
- `d` on the route in k9s shows `Accepted` and `ResolvedRefs`, and you know
  what each means.

## Where it gets hard

- A route that doesn't attach shows nothing in `curl`; the reason is in the
  route's status. Usual causes: wrong Gateway namespace in `parentRefs`, or
  the listener's `allowedRoutes` excluding the route's namespace.
- A `ReferenceGrant` is needed when a route points at a Service in another
  namespace.
- `curl` without the `Host` header gets a 404 from Envoy: no route matches.

## Links

- <https://gateway-api.sigs.k8s.io/guides/http-routing/>
- <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
- <https://docs.cilium.io/en/stable/observability/hubble/>
