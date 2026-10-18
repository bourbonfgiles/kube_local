# 8. Image promotion with Git writeback

Flux watches the registry, picks the newest tag that matches a policy, and
commits it to this repo. The commit is the deployment, so Git stays the record
of what's running.

EKS equivalent: the same objects, pointed at ECR with an IAM role for the
image-reflector-controller.

## Before you start

- Bootstrapped with `--components-extra image-reflector-controller,image-automation-controller`
  and `--read-write-key` (step 2). If you weren't: delete the `flux-system`
  Secret in `flux-system`, then re-run bootstrap with both. A read-only key
  isn't upgraded in place.
- An image of your own in the local registry (step 7). The producer or
  consumer from step 11 is a good one.

## Tasks

1. Deploy `k3d-registry.localhost:5000/<app>:1.0.0` through a HelmRelease
   (or a plain Deployment) in Git.
2. `ImageRepository` (`image.toolkit.fluxcd.io/v1`) for
   `k3d-registry.localhost:5000/<app>`, `insecure: true`.
3. `ImagePolicy` with `policy.semver.range: ">=1.0.0 <2.0.0"`.
4. A marker comment on the line holding the tag:
   `tag: 1.0.0 # {"$imagepolicy": "<ns>:<policy>:tag"}`.
5. `ImageUpdateAutomation`: `sourceRef` the `flux-system` GitRepository,
   `git.checkout.ref.branch: master`, `git.commit.author`, `update.path:
   ./apps`, `update.strategy: Setters`.
6. Push `1.0.1` from the host. Watch `flux get images all -A`, then the commit
   on GitHub, then the rollout.
7. Promotion: two environments (say namespaces `dev` and `prod`, one
   HelmRelease each). `dev`'s policy takes prereleases (`>=1.0.0-0`); `prod`'s
   takes only stable tags. Push `1.1.0-rc.1`, see only `dev` move, then push
   `1.1.0`.
8. Gate `prod` with review: a second automation with `git.push.branch:
   flux-image-updates` writes to a branch instead, and you merge a PR to
   promote.

## Done when

- Pushing an image is the only thing you do by hand, and Git history shows each
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
- With no tag immutability (step 7), overwriting a tag deploys new content
  without a commit.

## Links

- <https://fluxcd.io/flux/guides/image-update/>
- <https://fluxcd.io/flux/components/image/imagepolicies/>
- <https://fluxcd.io/flux/components/image/imageupdateautomations/>
