# 1. Cilium and Gateway API by hand

Learn Gateway API and Hubble with `helm` and `kubectl` before GitOps hides the
moving parts. The Gateway files you write here stay on disk and become Flux's
first objects in lesson 2; everything else is deleted at the end.

EKS equivalent: Cilium as the CNI on EKS, or the AWS Load Balancer Controller
reading Gateway API objects.

## Before you start

On your machine: `kubectl`, `helm`, `cilium`, `hubble`, `k9s`, `curl`.

In the cluster:

- `cilium --context k3d-dev status` is all green.
- k9s `:gatewayclasses` shows `cilium` with `ACCEPTED True`.

## Objects

| Kind | File | Kept |
| --- | --- | --- |
| Namespace `gateway` | `infrastructure/base/gateway/namespace.yaml` | Yes, lesson 2 |
| Gateway `web` | `infrastructure/base/gateway/gateway.yaml` | Yes, lesson 2 |
| Helm releases `blue`, `green` (podinfo) in `demo` | none, `helm install` | No |
| HTTPRoute `demo` in `demo` | `demo/route.yaml` | No, delete the folder |

## Tasks

1. Look around:
   ```sh
   cilium --context k3d-dev config view | grep -iE 'gateway|kube-proxy|l2'
   ```
   In k9s, `:pods -n kube-system`, pick a `cilium-` pod, `s` for a shell, and:
   ```sh
   # in the pod shell
   cilium-dbg service list
   ```
   That table is what kube-proxy would otherwise do in iptables.
2. Hubble. In one terminal, `cilium --context k3d-dev hubble port-forward`;
   in another, `hubble observe -f`. `cilium --context k3d-dev hubble ui` opens
   the graph.
3. Two podinfo releases, so you have two backends to route between:
   ```sh
   helm --kube-context k3d-dev install blue oci://ghcr.io/stefanprodan/charts/podinfo \
     --version 6.7.1 -n demo --create-namespace --set ui.message=blue
   helm --kube-context k3d-dev install green oci://ghcr.io/stefanprodan/charts/podinfo \
     --version 6.7.1 -n demo --set ui.message=green
   ```
4. The Gateway. Write both files, then
   `kubectl --context k3d-dev apply -f infrastructure/base/gateway/`:
   ```yaml
   # infrastructure/base/gateway/namespace.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: gateway
   ```
   ```yaml
   # infrastructure/base/gateway/gateway.yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: Gateway
   metadata:
     name: web
     namespace: gateway
   spec:
     gatewayClassName: cilium
     listeners:
       - name: http
         protocol: HTTP
         port: 80
         allowedRoutes:
           namespaces:
             from: All
   ```
5. k9s `:gateways` until `PROGRAMMED True` with an address (usually
   `10.89.0.200`). `:svc -n gateway` shows the LoadBalancer Service Cilium
   made for it.
6. A route to `blue`, then `kubectl --context k3d-dev apply -f demo/route.yaml`:
   ```yaml
   # demo/route.yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: demo
     namespace: demo
   spec:
     parentRefs:
       - name: web
         namespace: gateway
     hostnames: [demo.kube.internal]
     rules:
       - backendRefs:
           - name: blue-podinfo
             port: 9898
   ```
   `curl -H 'Host: demo.kube.internal' http://10.89.0.200/`.
7. Edit the file and re-apply after each step: a rule for `/green` to
   `green-podinfo` (with a `URLRewrite` filter so podinfo sees `/`), a header
   match `x-colour: green`, then a 90/10 split with `weight` on two
   `backendRefs`.
8. Watch the requests in Hubble. The source is `(ingress)`, Cilium's Envoy.
9. Clean up:
   ```sh
   kubectl --context k3d-dev delete -f demo/route.yaml -f infrastructure/base/gateway/gateway.yaml
   helm --kube-context k3d-dev uninstall -n demo blue green
   kubectl --context k3d-dev delete namespace demo gateway
   rm -r demo
   ```
   Keep `infrastructure/base/gateway/` for lesson 2.

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
- The podinfo Service is `<release>-podinfo`, so `blue-podinfo`. Check
  `:svc -n demo` if a backend shows `ResolvedRefs False`.

## Links

- <https://gateway-api.sigs.k8s.io/guides/http-routing/>
- <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
- <https://docs.cilium.io/en/stable/observability/hubble/>
