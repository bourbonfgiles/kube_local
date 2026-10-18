# 8. Image promotion with Git writeback

Flux watches the registry, picks the newest tag that matches a policy, and
commits it to this repo. The commit is the deployment, so Git stays the record
of what's running. Releasing a version is just mirroring a tag (lesson 7).

EKS equivalent: the same objects, pointed at ECR with an IAM role for the
image-reflector-controller.

## Before you start

- Bootstrapped with `--components-extra image-reflector-controller,image-automation-controller`
  and `--read-write-key` (lesson 2). If you weren't: delete the `flux-system`
  Secret in `flux-system`, then re-run bootstrap with both. A read-only key
  isn't upgraded in place.
- podinfo `6.7.0` running from the local registry (lesson 7).

## Tasks

1. `ImageRepository` (`image.toolkit.fluxcd.io/v1`) for
   `k3d-registry.localhost:5000/podinfo`, `insecure: true`.
2. `ImagePolicy` with `policy.semver.range: ">=6.0.0 <7.0.0"`.
3. A marker comment on the tag line in podinfo's HelmRelease values:
   `tag: 6.7.0 # {"$imagepolicy": "<ns>:<policy>:tag"}`.
4. `ImageUpdateAutomation`: `sourceRef` the `flux-system` GitRepository,
   `git.checkout.ref.branch: master`, `git.commit.author`, `update.path:
   ./apps`, `update.strategy: Setters`.
5. Release: mirror `6.7.1` with skopeo. Watch k9s `:imagepolicies`, then the
   Flux commit on GitHub, then the rollout.
6. Two environments: namespaces `dev` and `prod`, a podinfo HelmRelease in
   each, one policy per environment. `dev`'s range takes prereleases
   (`>=6.0.0-0`); `prod`'s takes only stable tags.
7. Promote: re-tag an upstream release as `6.8.0-rc.1` while mirroring
   (`skopeo copy ... localhost:5050/podinfo:6.8.0-rc.1`). Only `dev` moves.
   Mirror it again as `6.8.0` and `prod` follows.
8. Gate `prod` with review: a second automation with `git.push.branch:
   flux-image-updates` writes to a branch instead, and you merge a PR to
   promote.

## Done when

- Mirroring a tag is the only thing you do by hand, and Git history shows each
  promotion as a Flux commit.

## Where it gets hard

- Flux pushes commits to the repo, so your local clone falls behind. Pull
  before every commit.
- The marker must be on the same line as the value it updates, and the policy
  reference must match namespace and name exactly. A typo means nothing
  happens, with no error.
- The reflector polls on an `interval`; nothing happens instantly.
- Semver ranges don't match prerelease tags unless the range includes a
  prerelease part (`-0`).
- With no tag immutability, overwriting a tag deploys new content without a
  commit.

## Links

- <https://fluxcd.io/flux/guides/image-update/>
- <https://fluxcd.io/flux/components/image/imagepolicies/>
- <https://fluxcd.io/flux/components/image/imageupdateautomations/>
