# 7. The registry (ECR stand-in)

The local stand-in for ECR is the k3d registry the dotfiles create: a CNCF
Distribution (`registry:2`) container outside the cluster, so images survive
`k3d cluster delete`.

| ECR | Here |
| --- | --- |
| `<acct>.dkr.ecr.<region>.amazonaws.com/<repo>` | `localhost:5050/<repo>` from the host, `k3d-registry.localhost:5000/<repo>` from nodes and pods |
| IAM auth, `aws ecr get-login-password` | None |
| TLS | Plain HTTP |
| Tag immutability | Not available; tags can be overwritten |
| Scan on push, lifecycle policies | Not available |
| Nodes pull via instance role | Nodes pull through a mirror in the k3s registry config |

## Tasks

1. Build anything with Podman and tag it `localhost:5050/hello:1.0.0`.
2. `podman push --tls-verify=false localhost:5050/hello:1.0.0`.
3. Browse it: `curl localhost:5050/v2/_catalog`, `curl localhost:5050/v2/hello/tags/list`,
   or `skopeo list-tags --tls-verify=false docker://localhost:5050/hello`.
4. Run it in the cluster with image `k3d-registry.localhost:5000/hello:1.0.0`.
5. Push `1.0.0` again with different content. The tag now points somewhere
   else; that's what ECR's immutability setting prevents.
6. Optional, closer to ECR: run Zot instead (built-in auth, RBAC, scanning),
   and give Flux credentials with a `secretRef` on the `ImageRepository` in
   step 8.

## Done when

- You can push from the host and pull from a pod without thinking about which
  name to use.

## Where it gets hard

- One registry, three names: `localhost:5050` (host), `k3d-registry.localhost:5000`
  (nodes, pods), and the container name. Pods can't use `localhost:5050`.
- `curl` from a pod to `k3d-registry.localhost` is refused, because curl maps
  every `*.localhost` name to `127.0.0.1`. Use `wget` or `curl --resolve`.
- Plain HTTP means `--tls-verify=false` for Podman and `insecure: true` for
  Flux.
- Image promotion by semver assumes tags never change, and nothing here
  enforces it.

## Links

- <https://k3d.io/stable/usage/registries/>
- <https://distribution.github.io/distribution/>
- <https://zotregistry.dev/>
