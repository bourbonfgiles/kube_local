# 4. cert-manager and HTTPS

Right now nothing listens on 443, so `https://` fails everywhere. This adds an
HTTPS listener to the Gateway with certificates your machine trusts. Local
trust steps are for Bazzite 44 with Zen (Flatpak).

EKS equivalent: cert-manager with Let's Encrypt over Route53 DNS-01, or ACM on
the load balancer.

## You don't need to own a CA

Public CAs won't issue for `.internal`, so you make a private one. A CA is just
a key pair your machine is told to trust. mkcert creates one, and cert-manager
signs every Gateway certificate with it. The CA lives on your machine, so it
survives cluster rebuilds and you only trust it once.

Whoever holds the CA key can mint a certificate for any site your machine will
believe. Never put `rootCA-key.pem` in Git unencrypted.

## Before you start

- Flux (lesson 2) and ExternalDNS (lesson 3), so names resolve.
- `mkcert` (brew).

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
2. Check: `trust list | grep -i -A2 mkcert`.
3. Rebuild brew's bundle, which copies the system store only at install time:
   `brew postinstall ca-certificates`.
4. Zen can only see `~/Downloads`, so copy the public certificate there:
   `cp "$(mkcert -CAROOT)/rootCA.pem" ~/Downloads/kube-local-ca.pem`.
5. In Zen: `about:preferences#privacy` > Certificates > View Certificates >
   Authorities > Import, pick the file, tick "Trust this CA to identify
   websites". Zen has two profiles here; do it in each one you use.
6. Delete `~/Downloads/kube-local-ca.pem`.

## Tasks

1. A `tls` Secret in namespace `cert-manager` from the CA, created by hand
   (lesson 5 can move it into Git encrypted):
   ```sh
   kubectl -n cert-manager create secret tls local-ca \
     --cert="$(mkcert -CAROOT)/rootCA.pem" --key="$(mkcert -CAROOT)/rootCA-key.pem"
   ```
2. cert-manager as a HelmRelease from `oci://quay.io/jetstack/charts/cert-manager`
   with `crds.enabled: true` and Gateway API support:
   ```yaml
   config:
     apiVersion: controller.config.cert-manager.io/v1alpha1
     kind: ControllerConfiguration
     enableGatewayAPI: true
   ```
3. A `ClusterIssuer` of type `ca` using `local-ca`.
4. On the Gateway: annotation `cert-manager.io/cluster-issuer: <issuer>`, and an
   HTTPS listener on 443 with `hostname: "*.kube.internal"`, `tls.mode:
   Terminate`, and `certificateRefs` naming a Secret that doesn't exist yet.
5. k9s `:certificates` until ready. cert-manager created it from the listener.
6. `curl https://podinfo.kube.internal/`, then Zen.
7. Redirect HTTP to HTTPS: an `HTTPRoute` attached to the HTTP listener
   (`sectionName`) with a `RequestRedirect` filter.

## Done when

- Zen shows a padlock for `*.kube.internal` with no warnings.
- A cluster rebuild brings HTTPS back without trusting anything again.

## Where it gets hard

- Brew's `curl` fails with "unable to get local issuer certificate" until step
  3 of the trust setup. `/usr/bin/curl` works straight away.
- If Zen has DNS over HTTPS on, it asks the DoH provider, which has never heard
  of `kube.internal`. Add `kube.internal` under DNS over HTTPS > Manage
  Exceptions in `about:preferences#privacy`.
- The `cert-manager` namespace must exist before the CA Secret. Create the
  HelmRelease first, or the namespace by hand.
- cert-manager ignores listeners without a `hostname`.
- `*.kube.internal` doesn't cover `kube.internal` itself, or two levels deep
  (`a.b.kube.internal`).
- Gateway API support is off unless enabled in the controller config;
  annotations on the Gateway do nothing without it.

## Links

- <https://cert-manager.io/docs/usage/gateway/>
- <https://cert-manager.io/docs/configuration/ca/>
- <https://github.com/FiloSottile/mkcert>
- <https://docs.fedoraproject.org/en-US/quick-docs/using-shared-system-certificates/>
