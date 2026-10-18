# Extending the cluster

Next steps on top of the platform, roughly in order. Each is an outline, not a
manifest: the objects to write, the values that matter here, and what to check.
Everything goes under `clusters/dev/` once Flux is in. Pin every chart version.

## 1. Flux

Docs: <https://fluxcd.io/flux/installation/bootstrap/github/>

1. Fine-grained GitHub token on `kube_local`: Administration read/write (for the
   deploy key), Contents read/write, Metadata read.
2. `flux check --pre --context k3d-dev`.
3. Bootstrap:
   ```sh
   export GITHUB_TOKEN=...
   flux bootstrap github --context k3d-dev \
     --owner bourbonfgiles --repository kube_local --personal --private=false \
     --branch master --path clusters/dev \
     --components-extra image-reflector-controller,image-automation-controller \
     --read-write-key
   ```
   The image controllers and write key are for step 8; adding them now avoids a
   second bootstrap.
4. `git pull`: bootstrap committed `clusters/dev/flux-system/`.
5. `flux get all -A`. Anything you push under `clusters/dev/` now gets applied.

Flux reads GitHub, not this checkout: push before expecting a change.

| Argo CD | Flux |
| --- | --- |
| `Application` (Git path) | `GitRepository` + `Kustomization` (Flux's sync object; you never write Kustomize) |
| `Application` (Helm) | `HelmRepository` / `OCIRepository` + `HelmRelease` |
| Auto-sync, self-heal | `interval`; `spec.driftDetection.mode: enabled` on a HelmRelease |
| Sync now / pause | `flux reconcile ... --with-source` / `flux suspend`, `flux resume` |
| UI | None; `flux get`, `flux events`, `flux logs`, `k9s` |

## 2. Gateway and a first route

Docs: <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>

1. A `Gateway` in its own namespace: `gatewayClassName: cilium`, an HTTP
   listener on 80, `allowedRoutes.namespaces.from: All`.
2. `kubectl get gateway -A`: wait for `PROGRAMMED True` and an address from the
   pool (usually `10.89.0.200`).
3. A test app as a `HelmRelease`. podinfo is small: `OCIRepository`
   `oci://ghcr.io/stefanprodan/charts/podinfo`, service port 9898.
4. An `HTTPRoute` in the app's namespace: `parentRefs` to the Gateway (name and
   namespace), hostname `podinfo.kube.internal`, backend the podinfo Service.
5. `curl -H 'Host: podinfo.kube.internal' http://10.89.0.200/`.
6. `hubble observe -n <app ns> -f` while you curl, to watch Envoy reach the pod.

Then try path matches, header matches and weighted `backendRefs`, the parts
Ingress never had.

## 3. ExternalDNS

Docs: <https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/>

1. `HelmRepository` `https://kubernetes-sigs.github.io/external-dns/`, chart
   `external-dns`.
2. Namespace `external-dns` and a Secret holding the TSIG secret. Copy it from
   `dns/externaldns-tsig` by hand for now; step 6 puts it in Git.
3. Values that work against this BIND:
   ```yaml
   provider:
     name: rfc2136
   sources: [service, gateway-httproute, gateway-grpcroute]
   policy: sync
   registry: txt
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
4. `kubectl -n external-dns logs deploy/external-dns -f`: look for
   `Adding RR` lines.
5. `dig @10.89.0.250 podinfo.kube.internal`, then `curl http://podinfo.kube.internal/`.
6. Delete the route: with `policy: sync` the record goes too.

The trailing dot on the host skips the pod's search list. On EKS, the overlay
becomes `provider.name: aws` plus an IAM role; the sources and policy stay, so
split base and local values like Cilium's.

## 4. cert-manager with a local CA

Docs: <https://cert-manager.io/docs/usage/gateway/>

ACME can't issue for `.internal`, so use your own CA.

1. Chart `oci://quay.io/jetstack/charts/cert-manager` (an `OCIRepository`).
2. Values: `crds.enabled: true`, and Gateway API support:
   ```yaml
   config:
     apiVersion: controller.config.cert-manager.io/v1alpha1
     kind: ControllerConfiguration
     enableGatewayAPI: true
   ```
   The Gateway API CRDs already exist, which cert-manager needs at startup.
3. A `selfSigned` `ClusterIssuer`.
4. A `Certificate` with `isCA: true` in the `cert-manager` namespace, issued by
   it, `secretName: local-ca`.
5. A `ca` `ClusterIssuer` using `local-ca`.
6. On the Gateway: annotation `cert-manager.io/cluster-issuer: <ca issuer>`, and
   an HTTPS listener on 443 with `hostname: "*.kube.internal"`, `tls.mode:
   Terminate`, `certificateRefs` naming a Secret. cert-manager creates the
   Certificate for it.
7. `kubectl get certificate -A` until `READY True`.
8. Trust the CA on the host: extract `ca.crt` from `local-ca`, then
   `sudo cp ca.crt /etc/pki/ca-trust/source/anchors/kube-local.crt && sudo update-ca-trust`
   (macOS: `security add-trusted-cert` into the System keychain).
9. `curl https://podinfo.kube.internal/`.

On EKS this becomes an ACME `ClusterIssuer` with Route53 DNS-01.

## 5. Flux owns Cilium

Docs: <https://fluxcd.io/flux/components/helm/helmreleases/>

1. `HelmRepository` `https://helm.cilium.io`.
2. `HelmRelease` named `cilium` in `kube-system`, same chart version as
   `bootstrap.sh`. Same name and namespace means Flux adopts the existing
   release.
3. Values: both files in order (base, then local), inline or as two ConfigMaps
   under `valuesFrom`. `valuesFrom` can't read files from Git.
4. Keep `k8sServiceHost`/`k8sServicePort`. Without them Cilium loses the API
   server and the cluster's networking with it.
5. `flux diff` or `helm get values cilium -n kube-system` before and after:
   the effective values shouldn't change.
6. Later upgrades: bump the version in Git only. Check the upgrade notes; some
   changes need a node restart.

`bootstrap.sh` still installs Cilium on a fresh cluster; Flux takes over once
bootstrapped.

## 6. Secrets in Git with SOPS

Docs: <https://fluxcd.io/flux/guides/mozilla-sops/>

1. `age-keygen -o age.agekey`. Keep it out of the repo.
2. `kubectl -n flux-system create secret generic sops-age --from-file=age.agekey`.
3. `.sops.yaml` at the repo root: `path_regex` for your secret files,
   `encrypted_regex: ^(data|stringData)$`, the age public key.
4. Write the Secret with `kubectl create secret ... --dry-run=client -o yaml`,
   then `sops --encrypt --in-place`.
5. A Flux `Kustomization` for that path with
   `decryption: {provider: sops, secretRef: {name: sops-age}}`.
6. Good first candidate: the ExternalDNS TSIG secret. If BIND's copy moves to
   Git too, `tsig-secret.sh` keeps whatever key is already in the cluster.

## 7. Monitoring

Docs: <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>

1. `HelmRepository` `https://prometheus-community.github.io/helm-charts`, chart
   `kube-prometheus-stack`, its own namespace.
2. k3s values: `kubeProxy.enabled: false` (there's no kube-proxy). The
   controller-manager, scheduler and etcd run inside the k3s server process, so
   their default scrape targets show as down; disable them or point them at the
   server node.
3. An `HTTPRoute` for Grafana, e.g. `grafana.kube.internal`.
4. Cilium metrics, via the Flux-owned Cilium values: `prometheus.enabled`,
   `operator.prometheus.enabled`, `hubble.metrics.enabled` (e.g. `dns`, `drop`,
   `tcp`, `flow`, `httpV2`), each with `serviceMonitor.enabled: true`.
5. `dependsOn` the monitoring HelmRelease from Cilium's, so the ServiceMonitor
   CRD exists first.
6. Import the Cilium and Hubble dashboards (Grafana.com IDs are in the Cilium
   docs).

## 8. Image promotion

Docs: <https://fluxcd.io/flux/guides/image-update/>

1. Build and push from the host:
   `podman push --tls-verify=false localhost:5050/<app>:1.0.0`.
2. Deploy it with image `k3d-registry.localhost:5000/<app>:1.0.0`.
3. `ImageRepository` for `k3d-registry.localhost:5000/<app>`, `insecure: true`
   (plain HTTP).
4. `ImagePolicy` with a semver range, e.g. `>=1.0.0 <2.0.0`.
5. Marker comment where the tag sits: `# {"$imagepolicy": "<ns>:<policy>"}`.
6. `ImageUpdateAutomation`: commit author, branch to push to, path
   `./clusters/dev`.
7. Push `1.0.1`, then `flux get images all -A` and watch Flux commit the bump.
8. Promotion: a second policy (say `prod`) with a stricter range, or one that
   only matches tags you push after testing.

## Other directions

- Network policy: lock a namespace down with `CiliumNetworkPolicy`, then
  allow the `ingress` entity so routes keep working (see Troubleshooting in
  the README).
- Gateway API extras: `GRPCRoute`, `ReferenceGrant` for cross-namespace
  backends, `BackendTLSPolicy`.
- Autoscaling: HPAs work now (`metrics-server` is bundled); KEDA for
  event-driven scaling.
- Policy: Kyverno, e.g. enforcing that images come from the local registry.
- BPF: `bpftrace` and the BCC tools on the host against pod processes;
  Hubble for the network side.
