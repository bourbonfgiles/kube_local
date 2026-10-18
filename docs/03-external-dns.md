# 3. ExternalDNS

Give routes real names: a hostname on an `HTTPRoute` becomes an A record in the
local zone, and goes away when the route does.

EKS equivalent: ExternalDNS writing to Route53, authenticated with an IAM role.
Here it writes to BIND over RFC2136, authenticated with a TSIG key.

## Before you start

- Flux working (step 2) and a route with a hostname under `kube.internal`.
- `dig @10.89.0.250 ns.kube.internal` answers `10.89.0.250`.

## Tasks

1. `HelmRepository` `https://kubernetes-sigs.github.io/external-dns/`, chart
   `external-dns`.
2. Namespace `external-dns` and a Secret with the TSIG secret, copied by hand
   from `dns/externaldns-tsig` (key `secret`). Step 5 moves it into Git.
3. Base values, the ones you'd keep on EKS:
   ```yaml
   sources: [service, gateway-httproute, gateway-grpcroute]
   policy: sync
   registry: txt
   ```
4. Local values:
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
         secretKeyRef: {name: <your secret>, key: secret}
   ```
5. `kubectl -n external-dns logs deploy/external-dns -f`: look for `Adding RR`.
6. `dig @10.89.0.250 podinfo.kube.internal`, then from the host
   `curl http://podinfo.kube.internal/`.
7. Delete the route and watch the record go. Look at the TXT records it keeps
   alongside each A record and work out why.

## Done when

- A new route is resolvable from the host within a minute, without touching
  DNS yourself.

## Where it gets hard

- The trailing dot on the host matters: without it the lookup walks the pod's
  search list first.
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
