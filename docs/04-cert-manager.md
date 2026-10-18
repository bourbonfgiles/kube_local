# 4. cert-manager and HTTPS

Right now nothing listens on 443, so `https://` fails everywhere. This adds an
HTTPS listener to the Gateway with certificates your machine trusts. Local
trust steps are for Bazzite 44 with Zen (Flatpak).

EKS equivalent: cert-manager with a Let's Encrypt `ClusterIssuer` over
Route53 DNS-01, or ACM on the load balancer. Same chart and base values; the
issuer is what differs.

## You don't need to own a CA

Public CAs won't issue for `.internal`, so you make a private one. A CA is just
a key pair your machine is told to trust. mkcert creates one, and cert-manager
signs every Gateway certificate with it. The CA lives on your machine, so it
survives cluster rebuilds and you only trust it once.

Whoever holds the CA key can mint a certificate for any site your machine will
believe. Never put `rootCA-key.pem` in Git unencrypted.

## Before you start

On your machine: `mkcert`, `/usr/bin/trust`, `kubectl`, `flux`, `curl`, Zen.

In the cluster: Flux (lesson 2) and ExternalDNS (lesson 3), so names resolve.

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `cert-manager` | `infrastructure/base/cert-manager/namespace.yaml` |
| OCIRepository | `cert-manager` | `infrastructure/base/cert-manager/source.yaml` |
| HelmRelease | `cert-manager` | `infrastructure/base/cert-manager/release.yaml` |
| ConfigMap | `cert-manager-values-base` | `infrastructure/base/cert-manager/values.yaml` |
| Secret (`kubernetes.io/tls`) | `local-ca` in `cert-manager` | By hand now; `secrets/local/` in lesson 5 |
| ClusterIssuer | `local-ca` | `infrastructure/local-config/cert-manager/cluster-issuer.yaml` |
| Kustomization | `infra-local-config` | `clusters/dev/infrastructure.yaml` |
| Gateway (moved, HTTPS added) | `gateway/web` | `infrastructure/local/gateway/gateway.yaml` |
| HTTPRoute | `gateway/https-redirect` | `infrastructure/local/gateway/redirect.yaml` |

## Trust on Bazzite 44

There are three trust stores on this machine, and each needs the CA once:

| Store | Used by | How |
| --- | --- | --- |
| System (`/etc/pki/ca-trust`) | `/usr/bin/curl`, Podman, most system tools | `mkcert -install` |
| Homebrew bundle | brew's `curl` (first on your PATH), brew's OpenSSL | `brew postinstall ca-certificates` |
| Zen's profile | Zen | Import in settings |

1. `mkcert -install`. It asks for sudo, writes the CA into
   `/etc/pki/ca-trust/source/anchors/` and runs `update-ca-trust`. It will warn
   that Firefox can't be configured; Zen is handled below.
2. Check: `/usr/bin/trust list | grep -i -A2 mkcert`. Use the full path: brew
   ships a different `trust`.
3. Rebuild brew's bundle, which copies the system store only at install time:
   `brew postinstall ca-certificates`.
4. Zen can only see `~/Downloads`, so copy the public certificate there:
   `cp "$(mkcert -CAROOT)/rootCA.pem" ~/Downloads/kube-local-ca.pem`.
5. In Zen: `about:preferences#privacy` > Certificates > View Certificates >
   Authorities > Import, pick the file, tick "Trust this CA to identify
   websites". Zen has two profiles here; do it in each one you use.
6. `rm ~/Downloads/kube-local-ca.pem`.

## Tasks

1. The chart. Source, release and base values, as in lesson 3 but from an OCI
   registry (`chartRef`, see the [layout example](README.md#helm-charts-and-their-values)):
   - OCIRepository `url: oci://quay.io/jetstack/charts/cert-manager`,
     `ref.tag: v1.21.2`.
   - HelmRelease `valuesFrom` only `cert-manager-values-base`: nothing about
     the chart itself is k3d-specific.
   - Base values, under `data.values.yaml` in ConfigMap
     `cert-manager-values-base`:
     ```yaml
     crds:
       enabled: true
     config:
       apiVersion: controller.config.cert-manager.io/v1alpha1
       kind: ControllerConfiguration
       enableGatewayAPI: true
     ```
   Push, and wait for k9s `:helmreleases -n cert-manager` to be `Ready`.
2. The CA Secret, by hand (lesson 5 moves it into Git, encrypted):
   ```sh
   kubectl --context k3d-dev -n cert-manager create secret tls local-ca \
     --cert="$(mkcert -CAROOT)/rootCA.pem" --key="$(mkcert -CAROOT)/rootCA-key.pem"
   ```
3. The issuer. Try it by hand first, then commit the same file:
   ```yaml
   # infrastructure/local-config/cert-manager/cluster-issuer.yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: local-ca
   spec:
     ca:
       secretName: local-ca
   ```
   ```sh
   kubectl --context k3d-dev apply -f infrastructure/local-config/cert-manager/cluster-issuer.yaml
   ```
   k9s `:clusterissuers` shows it `Ready`. For Flux, add a Kustomization
   `infra-local-config` to `clusters/dev/infrastructure.yaml`:
   `path: ./infrastructure/local-config`, `dependsOn: [{name: infra-local}]`.
   It's a separate layer because `ClusterIssuer` only exists once the chart
   has installed its CRDs; in `infra-local` it would block the ConfigMaps
   other charts are waiting for.
4. The Gateway now names a local hostname and issuer, so it moves to the local
   layer: `git mv infrastructure/base/gateway infrastructure/local/gateway`.
   On EKS its file would name your real domain and an ACME issuer. Then edit
   `infrastructure/local/gateway/gateway.yaml`:
   ```yaml
   metadata:
     name: web
     namespace: gateway
     annotations:
       cert-manager.io/cluster-issuer: local-ca
   spec:
     gatewayClassName: cilium
     listeners:
       - name: http
         ...                       # unchanged
       - name: https
         protocol: HTTPS
         port: 443
         hostname: "*.kube.internal"
         allowedRoutes:
           namespaces:
             from: All
         tls:
           mode: Terminate
           certificateRefs:
             - name: wildcard-kube-internal   # cert-manager creates it
   ```
5. Push. k9s `:certificates -n gateway` until `Ready`: cert-manager made the
   Certificate from the listener.
6. `curl https://podinfo.kube.internal/`, then Zen.
7. Redirect HTTP to HTTPS: an HTTPRoute in
   `infrastructure/local/gateway/redirect.yaml`, `parentRefs` the Gateway with
   `sectionName: http`, hostname `*.kube.internal`, and one rule with a
   `RequestRedirect` filter (`scheme: https`, `statusCode: 301`). Then give
   app routes `sectionName: https` so they don't also match plain HTTP.

## Done when

- Zen shows a padlock for `*.kube.internal` with no warnings.
- A cluster rebuild brings HTTPS back without trusting anything again.

## Where it gets hard

- Brew's `curl` fails with "unable to get local issuer certificate" until step
  3 of the trust setup. `/usr/bin/curl` works straight away.
- If Zen has DNS over HTTPS on, it asks the DoH provider, which has never heard
  of `kube.internal`. Add `kube.internal` under DNS over HTTPS > Manage
  Exceptions in `about:preferences#privacy`.
- The `cert-manager` namespace must exist before the CA Secret: let Flux create
  it in task 1 first.
- Moving the Gateway between layers deletes and recreates it, so routes drop
  for a moment. Expected here; on a real cluster you'd keep its file in place.
- cert-manager ignores listeners without a `hostname`.
- `*.kube.internal` doesn't cover `kube.internal` itself, or two levels deep
  (`a.b.kube.internal`).
- Gateway API support is off unless `enableGatewayAPI` is in the controller
  config; the annotation on the Gateway does nothing without it.

## Links

- <https://cert-manager.io/docs/usage/gateway/>
- <https://cert-manager.io/docs/configuration/ca/>
- <https://github.com/FiloSottile/mkcert>
- <https://docs.fedoraproject.org/en-US/quick-docs/using-shared-system-certificates/>
