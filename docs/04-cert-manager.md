# 4. cert-manager and HTTPS

Right now nothing listens on 443, so `https://` fails everywhere. This adds an
HTTPS listener to the Gateway with certificates your machine trusts.

EKS equivalent: cert-manager with Let's Encrypt over Route53 DNS-01, or ACM on
the load balancer.

## You don't need to own a CA

Public CAs won't issue for `.internal`, so you make a private one. A CA is just
a key pair your machine is told to trust. Two ways:

- mkcert (recommended): `mkcert -install` creates a CA and adds it to the
  system trust store in one command. cert-manager then signs with that CA.
- cert-manager only: cert-manager creates a self-signed CA in the cluster and
  you add its certificate to the trust store by hand. It's regenerated
  whenever the cluster is rebuilt, so you re-trust it each time.

Whoever holds the CA key can mint a certificate for any site your machine will
believe. Never put it in Git unencrypted.

## Before you start

- Flux (step 2) and ExternalDNS (step 3), so names resolve.
- `mkcert` (brew), plus `nss-tools` if you want Firefox or Chrome to trust it.

## Tasks

1. `mkcert -install`, then `mkcert -CAROOT` to find `rootCA.pem` and
   `rootCA-key.pem`.
2. A `tls` Secret in namespace `cert-manager` from those two files, created by
   hand (step 5 can move it into Git encrypted).
3. cert-manager as a HelmRelease from `oci://quay.io/jetstack/charts/cert-manager`
   with `crds.enabled: true` and Gateway API support:
   ```yaml
   config:
     apiVersion: controller.config.cert-manager.io/v1alpha1
     kind: ControllerConfiguration
     enableGatewayAPI: true
   ```
4. A `ClusterIssuer` of type `ca` using that Secret.
5. On the Gateway: annotation `cert-manager.io/cluster-issuer: <issuer>`, and an
   HTTPS listener on 443 with `hostname: "*.kube.internal"`, `tls.mode:
   Terminate`, and `certificateRefs` naming a Secret that doesn't exist yet.
6. `kubectl get certificate -A` until `READY True`. cert-manager created it from
   the listener.
7. `curl https://podinfo.kube.internal/`, then a browser.
8. Redirect HTTP to HTTPS: an `HTTPRoute` attached to the HTTP listener
   (`sectionName`) with a `RequestRedirect` filter.

## Done when

- The browser shows a padlock for `*.kube.internal` with no warnings.
- A cluster rebuild brings HTTPS back without re-trusting anything.

## Where it gets hard

- Bazzite browsers are Flatpaks with their own certificate stores, so mkcert
  can't reach them. Import `rootCA.pem` in the browser's settings once.
- cert-manager ignores listeners without a `hostname`.
- `*.kube.internal` doesn't cover `kube.internal` itself, or two levels deep
  (`a.b.kube.internal`).
- Gateway API support is off unless enabled in the controller config;
  annotations on the Gateway do nothing without it.
- The Gateway API CRDs must exist before cert-manager starts. They do here.

## Links

- <https://cert-manager.io/docs/usage/gateway/>
- <https://cert-manager.io/docs/configuration/ca/>
- <https://github.com/FiloSottile/mkcert>
