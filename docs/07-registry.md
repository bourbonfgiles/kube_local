# 7. The registry (ECR stand-in)

The local stand-in for ECR is the k3d registry the dotfiles create: a CNCF
Distribution (`registry:2`) container outside the cluster, so images survive
`k3d cluster delete`. You fill it the way many teams fill ECR: by mirroring
vendor images into it.

| ECR | Here |
| --- | --- |
| `<acct>.dkr.ecr.<region>.amazonaws.com/<repo>` | `localhost:5050/<repo>` from the host, `k3d-registry.localhost:5000/<repo>` from nodes and pods |
| IAM auth, `aws ecr get-login-password` | None |
| TLS | Plain HTTP |
| Tag immutability | Not available; tags can be overwritten |
| Scan on push, lifecycle policies | Not available |
| Pull-through cache | Not configured; you mirror by hand |

## Before you start

- `skopeo` (part of Fedora Atomic; `brew install skopeo` on macOS).

## Tasks

1. Mirror two podinfo releases:
   ```sh
   for t in 6.7.0 6.7.1; do
     skopeo copy --dest-tls-verify=false \
       docker://ghcr.io/stefanprodan/podinfo:$t \
       docker://localhost:5050/podinfo:$t
   done
   ```
2. See what's there: `skopeo list-tags --tls-verify=false docker://localhost:5050/podinfo`,
   or `curl localhost:5050/v2/_catalog`.
3. Point podinfo's HelmRelease at the mirror: `image.repository:
   k3d-registry.localhost:5000/podinfo`, `image.tag: 6.7.0`. In k9s, `d` on
   the pod shows where it pulled from.
4. `skopeo inspect` the same tag upstream and locally: the digests match, so
   it's the same image.
5. Copy `6.7.1` over the `6.7.0` tag. Nothing stops it; that's what ECR's
   immutability setting prevents. Put it back afterwards.
6. Optional, closer to ECR: Zot as a HelmRelease (built-in auth, RBAC,
   scanning), and give Flux credentials with a `secretRef` in lesson 8.

## Done when

- You can mirror a tag and have a pod pull it from the local registry.

## Where it gets hard

- One registry, three names: `localhost:5050` (host), `k3d-registry.localhost:5000`
  (nodes, pods), and the container name. Pods can't use `localhost:5050`.
- `curl` from a pod to `k3d-registry.localhost` is refused, because curl maps
  every `*.localhost` name to `127.0.0.1`. Use `wget` or `curl --resolve`.
- Plain HTTP means `--dest-tls-verify=false` for skopeo and `insecure: true`
  for Flux.
- Promotion by semver assumes tags never change, and nothing here enforces it.

## Links

- <https://k3d.io/stable/usage/registries/>
- <https://github.com/containers/skopeo>
- <https://zotregistry.dev/>
