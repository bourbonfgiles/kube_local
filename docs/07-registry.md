# 7. The registry (ECR stand-in)

The local stand-in for ECR is the k3d registry the dotfiles create: a CNCF
Distribution (`registry:2`) container outside the cluster, so images survive
`k3d cluster delete`. You fill it the way many teams fill ECR: by mirroring
vendor images into it.

| ECR | Here |
| --- | --- |
| `<acct>.dkr.ecr.<region>.amazonaws.com/<repo>` | `localhost:5050/<repo>` from your machine, `k3d-registry.localhost:5000/<repo>` from nodes and pods |
| IAM auth, `aws ecr get-login-password` | None |
| TLS | Plain HTTP |
| Tag immutability | Not available; tags can be overwritten |
| Scan on push, lifecycle policies | Not available |
| Pull-through cache | Not configured; you mirror by hand |

## Before you start

On your machine: `skopeo` (Bazzite base image; `brew install skopeo` on
macOS), `curl`, `jq`, `k9s`.

In the cluster: the registry container, which dotfiles creates with the
cluster. podinfo from lesson 2 for task 3.

## Objects

No new Kubernetes objects. The change is to podinfo's values:

| Kind | Name | File |
| --- | --- | --- |
| ConfigMap, changed | `podinfo/podinfo-values-local` | `apps/local/podinfo/values.yaml` |

The image location is local: on EKS the same keys would name your ECR repo.

## Tasks

1. Mirror two podinfo releases. `--all` copies every architecture, so the
   digest matches upstream:
   ```sh
   for t in 6.7.0 6.7.1; do
     skopeo copy --all --dest-tls-verify=false \
       docker://ghcr.io/stefanprodan/podinfo:$t \
       docker://localhost:5050/podinfo:$t
   done
   ```
2. See what's there:
   ```sh
   skopeo list-tags --tls-verify=false docker://localhost:5050/podinfo
   curl -s localhost:5050/v2/_catalog | jq
   ```
3. Point podinfo at the mirror. In `podinfo-values-local`:
   ```yaml
   image:
     repository: k3d-registry.localhost:5000/podinfo
     tag: 6.7.0
   ```
   Push. In k9s, `d` on the new pod shows the image it pulled.
4. Compare digests upstream and locally; they match, so it's the same image:
   ```sh
   skopeo inspect --format '{{.Digest}}' docker://ghcr.io/stefanprodan/podinfo:6.7.0
   skopeo inspect --tls-verify=false --format '{{.Digest}}' docker://localhost:5050/podinfo:6.7.0
   ```
5. Copy `6.7.1` over the `6.7.0` tag. Nothing stops it; that's what ECR's
   immutability setting prevents. Put it back afterwards.
6. Optional, closer to ECR: Zot as a HelmRelease (built-in auth, RBAC,
   scanning), then a `secretRef` on Flux's ImageRepository in lesson 8.

## Done when

- You can mirror a tag and have a pod pull it from the local registry.

## Where it gets hard

- One registry, two names: `localhost:5050` from your machine, and
  `k3d-registry.localhost:5000` from nodes and pods. Pods can't use
  `localhost:5050`.
- `curl` from a pod to `k3d-registry.localhost` is refused, because curl maps
  every `*.localhost` name to `127.0.0.1`. Use `wget` or `curl --resolve`.
- Plain HTTP means `--dest-tls-verify=false` for skopeo and `insecure: true`
  for Flux.
- Without `--all`, skopeo copies only your machine's architecture and the
  digest changes.
- Promotion by semver assumes tags never change, and nothing here enforces it.

## Links

- <https://k3d.io/stable/usage/registries/>
- <https://github.com/containers/skopeo>
- <https://zotregistry.dev/>
