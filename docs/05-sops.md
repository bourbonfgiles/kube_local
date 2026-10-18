# 5. Secrets in Git with SOPS

Encrypt Secrets so they can live in this public repo, and have Flux decrypt
them in the cluster.

EKS equivalent: SOPS with an AWS KMS key, or External Secrets reading AWS
Secrets Manager.

## Before you start

- `sops` and `age` (brew).
- Candidates: the ExternalDNS TSIG secret (step 3), the CA Secret (step 4).

## Tasks

1. `age-keygen -o ~/.config/sops/age/keys.txt`. Back it up somewhere safe. If you
   lose it, nothing in Git can be decrypted.
2. `kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=<that file>`.
3. `.sops.yaml` at the repo root: a rule with a `path_regex` for your secrets
   directory, `encrypted_regex: ^(data|stringData)$`, and the age public key.
4. Choose a directory outside `clusters/dev`, e.g. `secrets/dev/`.
5. Write a Secret with `kubectl create secret ... --dry-run=client -o yaml`,
   then `sops --encrypt --in-place` it. Check `data` is ciphertext and
   `metadata` is readable.
6. A Flux `Kustomization` under `clusters/dev/` pointing at `./secrets/dev` with
   `decryption: {provider: sops, secretRef: {name: sops-age}}`.
7. Push, then check the Secret in the cluster has the plain value.
8. Replace the hand-made TSIG secret in `external-dns` with the Git one. Use the
   value that's already in `dns/externaldns-tsig`, so BIND still accepts it.

## Done when

- `git grep` of the repo finds no plaintext secret, and a rebuilt cluster gets
  every secret back from Git plus the one age key.

## Where it gets hard

- Bootstrap's `flux-system` Kustomization applies everything under
  `clusters/dev` and has no decryption, so an encrypted file there fails to
  apply. That's why the secrets live elsewhere.
- `sops-age` itself can't be in Git. It's the one secret you recreate by hand
  after a rebuild.
- Editing: `sops <file>` decrypts into your editor and re-encrypts on save.
  Don't decrypt to disk.

## Links

- <https://fluxcd.io/flux/guides/mozilla-sops/>
- <https://github.com/getsops/sops>
