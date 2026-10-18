# 8. Image promotion with Git writeback

Flux watches the registry, picks the newest tag that matches a policy, and
commits it to this repo. The commit is the deployment, so Git stays the record
of what's running. Releasing a version is just mirroring a tag (lesson 7).

EKS equivalent: the same objects, pointed at ECR, with an IAM role for the
image-reflector-controller instead of `insecure: true`.

## Before you start

On your machine: `skopeo`, `flux`, `kubectl`, `git`, `k9s`.

In the cluster:

- Flux bootstrapped with
  `--components-extra image-reflector-controller,image-automation-controller`
  and `--read-write-key` (lesson 2). k9s `:deploy -n flux-system` shows both
  image controllers. If you bootstrapped without them, a read-only key isn't
  upgraded in place:
  ```sh
  kubectl --context k3d-dev -n flux-system delete secret flux-system
  ```
  then run lesson 2's bootstrap command again, with both flags.
- podinfo `6.7.0` running from the local registry (lesson 7).

## Objects

All in namespace `podinfo`. The automation only uses policies in its own
namespace, so they live together.

| Kind | Name | File |
| --- | --- | --- |
| ImageRepository | `podinfo` | `apps/local/podinfo/image.yaml` |
| ImagePolicy | `podinfo` | `apps/local/podinfo/image.yaml` |
| ImageUpdateAutomation | `podinfo` | `apps/local/podinfo/image.yaml` |
| HelmRelease, changed | `podinfo` | `apps/base/podinfo/release.yaml` (tag moves to `spec.values`) |
| ConfigMap, changed | `podinfo-values-local` | `apps/local/podinfo/values.yaml` (tag removed) |

They're local because they name the local registry and this cluster's branch.

## Tasks

1. Watch the registry and pick a tag:
   ```yaml
   # apps/local/podinfo/image.yaml
   apiVersion: image.toolkit.fluxcd.io/v1
   kind: ImageRepository
   metadata:
     name: podinfo
     namespace: podinfo
   spec:
     image: k3d-registry.localhost:5000/podinfo
     interval: 1m
     insecure: true
   ---
   apiVersion: image.toolkit.fluxcd.io/v1
   kind: ImagePolicy
   metadata:
     name: podinfo
     namespace: podinfo
   spec:
     imageRepositoryRef:
       name: podinfo
     policy:
       semver:
         range: ">=6.0.0 <7.0.0"
   ```
   Try it by hand first with
   `kubectl --context k3d-dev apply -f apps/local/podinfo/image.yaml`. k9s
   `:imagerepositories -n podinfo` lists the tags it found;
   `:imagepolicies -n podinfo` shows the one it picked. Then commit.
2. Move the tag where Flux can rewrite it. Flux can't edit inside a
   ConfigMap's `values.yaml` string, so the tag goes in the HelmRelease's
   `spec.values`, with a marker on the same line. Delete `image.tag` from
   `podinfo-values-local` and add to `apps/base/podinfo/release.yaml`:
   ```yaml
   spec:
     values:
       image:
         tag: 6.7.0 # {"$imagepolicy": "podinfo:podinfo:tag"}
   ```
   The marker reads `<namespace>:<policy name>:tag`.
3. The automation, appended to `image.yaml`:
   ```yaml
   ---
   apiVersion: image.toolkit.fluxcd.io/v1
   kind: ImageUpdateAutomation
   metadata:
     name: podinfo
     namespace: podinfo
   spec:
     interval: 5m
     sourceRef:
       kind: GitRepository
       name: flux-system
       namespace: flux-system
     git:
       checkout:
         ref:
           branch: master
       commit:
         author:
           name: fluxcdbot
           email: fluxcdbot@users.noreply.github.com
       push:
         branch: master
     update:
       path: ./apps
       strategy: Setters
   ```
   Push, then `git pull` before your next commit: Flux will be committing too.
4. Release: mirror `6.7.1` (lesson 7, task 1). Watch k9s `:imagepolicies`,
   then the Flux commit on GitHub, then the rollout in `:pods -n podinfo`.
5. Two environments: namespaces `podinfo-dev` and `podinfo-prod`, each with
   its own copy of these objects and a podinfo HelmRelease. `dev`'s range
   takes prereleases (`>=6.0.0-0`); `prod`'s takes only stable tags.
6. Promote. A release candidate, re-tagged from an upstream image while
   mirroring:
   ```sh
   skopeo copy --all --dest-tls-verify=false \
     docker://ghcr.io/stefanprodan/podinfo:6.7.1 \
     docker://localhost:5050/podinfo:6.8.0-rc.1
   ```
   Only `dev` moves. Mirror it again as `6.8.0` and `prod` follows.
7. Gate `prod` with review: in `prod`'s automation set `git.push.branch:
   flux-image-updates`. Flux writes to that branch instead, and you merge a PR
   to promote.

## Done when

- Mirroring a tag is the only thing you do by hand, and Git history shows each
  promotion as a Flux commit.

## Where it gets hard

- Flux pushes commits to the repo, so your local clone falls behind. Pull
  before every commit.
- The marker must be on the same line as the value, and the policy reference
  must match namespace and name exactly. A typo means nothing happens, with no
  error.
- `spec.values` beats every ConfigMap, so a tag left in a values ConfigMap is
  silently ignored.
- The reflector polls on its `interval`; nothing happens instantly.
- Semver ranges don't match prerelease tags unless the range has a
  prerelease part (`-0`).
- With no tag immutability, overwriting a tag deploys new content without a
  commit.

## Links

- <https://fluxcd.io/flux/guides/image-update/>
- <https://fluxcd.io/flux/components/image/imagepolicies/>
- <https://fluxcd.io/flux/components/image/imageupdateautomations/>
