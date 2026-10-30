# 3. ExternalDNS

> You end up with: every route's hostname resolving from your machine within
> a minute, with no DNS edits by hand.

## What it is

ExternalDNS is a controller that turns Kubernetes objects into DNS records.
It reads hostnames from its **sources** (here `HTTPRoute`s and Services),
works out the address each should point at, and writes the difference to a
DNS **provider**.

```mermaid
flowchart LR
  route["HTTPRoute<br/>podinfo.kube.internal"] --> gw["Gateway web<br/>status address 10.89.0.200"]
  gw --> ed["ExternalDNS<br/>source: gateway-httproute"]
  ed -->|"RFC2136 update,<br/>signed with TSIG key"| bind["BIND<br/>kube.internal on 10.89.0.250"]
  host["Your machine<br/>dotfiles DNS rule"] -->|"*.kube.internal ?"| bind
```

| Idea | Means |
| --- | --- |
| Source | Where names come from. For a route, the address comes from its Gateway's status, not the route. |
| Provider | Where records go. Route53 on AWS; here BIND, spoken to over RFC2136 (standard dynamic DNS updates). |
| TSIG | A shared secret that signs each update, so BIND only accepts changes from ExternalDNS. `bootstrap.sh` made one in `dns/externaldns-tsig`. |
| Registry | ExternalDNS writes a TXT record next to each A record saying it owns it, so it never deletes records it didn't create. |
| Policy | `sync` creates and deletes; `upsert-only` never deletes. |

BIND here is the local stand-in for a Route53 hosted zone. It starts empty.

## On EKS

The same chart with `provider.name: aws`, writing to Route53, authenticated
with an IAM role on its service account (IRSA or Pod Identity) instead of a
TSIG key. The sources, policy and registry values don't change.

## Requirements

**In the cluster**

- BIND answering: `dig @10.89.0.250 ns.kube.internal` returns `10.89.0.250`.
- The Gateway and podinfo's route `podinfo.kube.internal` from lesson 2.
- Flux (lesson 2).

**On your machine**: `kubectl`, `helm`, `flux`, `dig`, `curl`, and `sofka` or
`k9s` ([lesson 0](00-tools.md)). The
host resolves `kube.internal` through the dotfiles `dotfiles-kube-dns`
unit; `resolvectl status k3d0` should list `10.89.0.250`.

## By hand, for comparison

> [!NOTE]
> Read this, don't run it. Flux does the same from Git below.

By hand, ExternalDNS is one `helm` command with a base and a dev values
file:

**Example only: don't run it**
```sh
helm --kube-context k3d-dev upgrade --install external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ --version 1.23.0 \
  -n external-dns -f values-base.yaml -f values-dev.yaml
```

Each values file becomes a ConfigMap below, unchanged, under
`data.values.yaml`. `helm show values external-dns --repo
https://kubernetes-sigs.github.io/external-dns/` lists every key.

## Install with Flux

### 1. The TSIG secret

ExternalDNS needs the same key BIND has. A Secret can't go in Git in plain
text, so this stays by hand until lesson 5 encrypts it. Copy it into a new
namespace:

```sh
kubectl --context k3d-dev create namespace external-dns
kubectl --context k3d-dev -n external-dns create secret generic externaldns-tsig \
  --from-literal=secret="$(kubectl --context k3d-dev -n dns get secret externaldns-tsig \
    -o jsonpath='{.data.secret}' | base64 -d)"
kubectl --context k3d-dev -n external-dns get secret externaldns-tsig \
  -o jsonpath='{.data.secret}' | base64 -d
```

The last command should print the same key BIND has.

sofka / k9s: `:secrets external-dns`, `x` to decode

### 2. The files

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `external-dns` | `~/repos/personal/kube_local/infrastructure/base/external-dns/namespace.yaml` |
| HelmRepository | `external-dns` | `~/repos/personal/kube_local/infrastructure/base/external-dns/source.yaml` |
| HelmRelease | `external-dns` | `~/repos/personal/kube_local/infrastructure/base/external-dns/release.yaml` |
| ConfigMap | `external-dns-values-base` | `~/repos/personal/kube_local/infrastructure/base/external-dns/values.yaml` |
| ConfigMap | `external-dns-values-dev` | `~/repos/personal/kube_local/infrastructure/dev/external-dns/values.yaml` |
| Secret | `externaldns-tsig` | By hand, above; lesson 5 puts it in Git encrypted |

This chart comes from a classic Helm repository, so the release uses
`chart.spec` with a `HelmRepository`, where podinfo used `chartRef` with an
`OCIRepository`.

```sh
mkdir -p ~/repos/personal/kube_local/infrastructure/base/external-dns ~/repos/personal/kube_local/infrastructure/dev/external-dns
```

**Write `~/repos/personal/kube_local/infrastructure/base/external-dns/namespace.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/external-dns/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
```

**Write `~/repos/personal/kube_local/infrastructure/base/external-dns/source.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/external-dns/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: external-dns
  namespace: external-dns
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/external-dns/
```

**Write `~/repos/personal/kube_local/infrastructure/base/external-dns/release.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/external-dns/release.yaml
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
      name: external-dns-values-${CLUSTER_NAME}
```

What you'd keep on EKS:

**Write `~/repos/personal/kube_local/infrastructure/base/external-dns/values.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/base/external-dns/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: external-dns-values-base
  namespace: external-dns
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
    sources: [service, gateway-httproute, gateway-grpcroute]
    policy: sync
    registry: txt
```

What's local: BIND as the provider, and the key.

**Write `~/repos/personal/kube_local/infrastructure/dev/external-dns/values.yaml`**
```yaml
# ~/repos/personal/kube_local/infrastructure/dev/external-dns/values.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: external-dns-values-dev
  namespace: external-dns
  labels:
    reconcile.fluxcd.io/watch: Enabled
data:
  values.yaml: |
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

If you didn't adopt Cilium in lesson 2, this is the first file under
`~/repos/personal/kube_local/infrastructure/dev/`, so add `infra-dev` in the same commit. If you did,
the file already looks like this:

**Replace `~/repos/personal/kube_local/clusters/dev/infrastructure.yaml`**
```yaml
# ~/repos/personal/kube_local/clusters/dev/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-base
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/base
  prune: true
  postBuild:
    substitute:
      CLUSTER_NAME: dev
      CLUSTER_DOMAIN: kube.internal
# ── new ──
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-dev
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  dependsOn:
    - name: infra-base
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/dev
  prune: true
# ── end new ──
```

### 3. Push and check

```sh
git -C ~/repos/personal/kube_local add ~/repos/personal/kube_local/clusters/ ~/repos/personal/kube_local/infrastructure/
git -C ~/repos/personal/kube_local commit -m "ExternalDNS with Flux"
git -C ~/repos/personal/kube_local push
flux --context k3d-dev reconcile kustomization flux-system --with-source
kubectl --context k3d-dev get helmreleases -n external-dns -w
```

sofka / k9s: `:helmreleases external-dns`

```sh
kubectl --context k3d-dev -n external-dns logs deploy/external-dns -f
```

Look for `Adding RR` lines. For only the failures, pipe through
`grep -iE 'error|warn'`.

sofka / k9s: `:pods external-dns`, `l`. Only the failures: sofka `ctrl-z`
in the logs view; k9s `/error`.

```sh
dig +short @10.89.0.250 podinfo.kube.internal
curl -s http://podinfo.kube.internal/ | jq .message
dig @10.89.0.250 -t TXT podinfo.kube.internal
```

The TXT record is the ownership record: it names `k3d-dev`.

## Iterate

Every change is a commit. New or changed lines sit between `# ── new ──` and
`# ── end new ──`.

### Changes worth knowing

Each row is one commit, then its revert. What happens is the point; try any you like.

| Change | File | What happens |
| --- | --- | --- |
| Add `"hello.${CLUSTER_DOMAIN}"` to `hostnames` | `~/repos/personal/kube_local/apps/base/podinfo/route.yaml` | An A record and a TXT ownership record within ExternalDNS's 1m interval. Take it off again and both go. |
| `policy: upsert-only` | `~/repos/personal/kube_local/infrastructure/base/external-dns/values.yaml` | Creates and updates, never deletes: a hostname taken off a route keeps its record. `sync` deletes it. Push the policy before the route change, or the delete happens first. |
| Drop `--rfc2136-axfr` | `~/repos/personal/kube_local/infrastructure/dev/external-dns/values.yaml` | ExternalDNS can't list the zone, so it can't work out what to delete; its logs say so. |

## Exercises

1. In Git, a Service of `type: LoadBalancer` with the annotation
   `external-dns.alpha.kubernetes.io/hostname: lb.kube.internal`. Cilium gives
   it an address from the pool; ExternalDNS names it.
2. Restart BIND
   (`kubectl --context k3d-dev -n dns rollout restart deploy/bind`, or `r` on
   it in `:deploy dns`). The zone lives in an
   `emptyDir`, so records vanish. Time how long until ExternalDNS puts them
   back.
3. Harder: a second ExternalDNS HelmRelease in Git, in its own namespace,
   with `txtOwnerId: other`. Work
   out from the TXT records why neither deletes the other's records, and what
   happens when both claim the same name.

## Where it gets hard

- The trailing dot on `--rfc2136-host` matters: without it the lookup walks
  the pod's DNS search list first.
- Without `--rfc2136-axfr` it can't read the zone back, so it never deletes
  anything.
- A Gateway without an address produces no records for its routes.
- On your machine, names only resolve through the dotfiles DNS unit. If `dig
  @10.89.0.250` works but `curl` doesn't, it's the host side:
  `systemctl status dotfiles-kube-dns`.
- Errors from BIND show only in ExternalDNS's logs, often as a terse
  `NOTAUTH` or `REFUSED`. Those usually mean a wrong key name, algorithm or
  zone. A sofka extra ([lesson 0](00-tools.md)): `ctrl-z` in the logs view
  hides everything but warnings and errors.

## Links

- <https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/>
- <https://kubernetes-sigs.github.io/external-dns/latest/docs/sources/gateway-api/>
