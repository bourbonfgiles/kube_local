# 3. ExternalDNS

Give routes real names: a hostname on an `HTTPRoute` becomes an A record in the
local zone, and goes away when the route does.

EKS equivalent: ExternalDNS writing to Route53, authenticated with an IAM role.
Here it writes to BIND over RFC2136, authenticated with a TSIG key. Same chart;
only the local values differ.

## Before you start

On your machine: `kubectl`, `flux`, `dig`, `curl`, `k9s`.

In the cluster:

- Flux syncing the layers (lesson 2), and podinfo's route with
  `podinfo.kube.internal`.
- `dig @10.89.0.250 ns.kube.internal` answers `10.89.0.250`: BIND from
  `bootstrap.sh` is up.

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `external-dns` | `infrastructure/base/external-dns/namespace.yaml` |
| HelmRepository | `external-dns` | `infrastructure/base/external-dns/source.yaml` |
| HelmRelease | `external-dns` | `infrastructure/base/external-dns/release.yaml` |
| ConfigMap | `external-dns-values-base` | `infrastructure/base/external-dns/values.yaml` |
| ConfigMap | `external-dns-values-local` | `infrastructure/local/external-dns/values.yaml` |
| Secret | `externaldns-tsig` | By hand now; `secrets/local/` in lesson 5 |

All in namespace `external-dns`.

## Tasks

1. The Secret. BIND already has the key in namespace `dns`; copy it:
   ```sh
   kubectl --context k3d-dev create namespace external-dns
   kubectl --context k3d-dev -n external-dns create secret generic externaldns-tsig \
     --from-literal=secret="$(kubectl --context k3d-dev -n dns get secret externaldns-tsig \
       -o jsonpath='{.data.secret}' | base64 -d)"
   ```
   The namespace also goes in `namespace.yaml`; Flux adopts the one you made.
2. Source and release. A classic Helm repository, so `chart.spec` rather than
   `chartRef`:
   ```yaml
   # infrastructure/base/external-dns/source.yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: external-dns
     namespace: external-dns
   spec:
     interval: 1h
     url: https://kubernetes-sigs.github.io/external-dns/
   ---
   # infrastructure/base/external-dns/release.yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: external-dns
     namespace: external-dns
   spec:
     interval: 10m
     chart:
       spec:
         chart: external-dns
         version: 1.23.0
         sourceRef:
           kind: HelmRepository
           name: external-dns
     valuesFrom:
       - kind: ConfigMap
         name: external-dns-values-base
       - kind: ConfigMap
         name: external-dns-values-local
   ```
3. Base values, the ones you'd keep on EKS. In
   `infrastructure/base/external-dns/values.yaml`, ConfigMap
   `external-dns-values-base`, under `data.values.yaml`:
   ```yaml
   sources: [service, gateway-httproute, gateway-grpcroute]
   policy: sync
   registry: txt
   ```
4. Local values, in `infrastructure/local/external-dns/values.yaml`,
   ConfigMap `external-dns-values-local`. On EKS this file would instead set
   `provider.name: aws` and a service account role.
   ```yaml
   provider:
     name: rfc2136
   txtOwnerId: k3d-dev
   domainFilters: [kube.internal]
   extraArgs:
     - --rfc2136-host=bind.dns.svc.cluster.local.
     - --rfc2136-port=53
     - --rfc2136-zone=kube.internal
     - --rfc2136-tsig-keyname=externaldns
     - --rfc2136-tsig-secret-alg=hmac-sha256
     - --rfc2136-axfr
   env:
     - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET
       valueFrom:
         secretKeyRef:
           name: externaldns-tsig
           key: secret
   ```
5. If `infra-local` doesn't exist yet (you haven't adopted Cilium), add it to
   `clusters/dev/infrastructure.yaml` as lesson 2 describes. Push.
6. k9s `:helmreleases -n external-dns` until `Ready`, then `:pods -n
   external-dns`, `l` for logs: look for `Adding RR`.
7. `dig @10.89.0.250 podinfo.kube.internal`, then from the host
   `curl http://podinfo.kube.internal/`.
8. Delete the route from Git and watch the record go. Look at the TXT records
   it keeps alongside each A record (`dig @10.89.0.250 -t TXT ...`) and work
   out why.

## Done when

- A new route is resolvable from the host within a minute, without touching
  DNS yourself.

## Where it gets hard

- The trailing dot on `--rfc2136-host` matters: without it the lookup walks
  the pod's DNS search list first.
- Without `--rfc2136-axfr` it can't read the zone back, so it never deletes
  anything.
- For Gateway API sources, the record's address comes from the Gateway's
  status, so a Gateway without an address produces no records.
- BIND keeps the zone in an `emptyDir`; a BIND restart empties it until the
  next sync.
- On the host, `kube.internal` only resolves once the dotfiles `k8s` step has
  installed `dotfiles-kube-dns.service`.

## Links

- <https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/>
- <https://kubernetes-sigs.github.io/external-dns/latest/docs/sources/gateway-api/>
