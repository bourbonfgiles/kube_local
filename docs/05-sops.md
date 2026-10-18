# 5. Secrets in Git with SOPS

Encrypt Secrets so they can live in this public repo, and have Flux decrypt
them in the cluster. The two hand-made Secrets from lessons 3 and 4 move into
Git.

EKS equivalent: SOPS with an AWS KMS key instead of an age key, or External
Secrets reading AWS Secrets Manager.

## Before you start

On your machine: `sops`, `age` (it includes `age-keygen`), `kubectl`, `flux`,
`git`.

In the cluster: Flux (lesson 2). Secrets `externaldns-tsig` in `external-dns`
(lesson 3) and `local-ca` in `cert-manager` (lesson 4), if you did those.

## Objects

| Kind | Name | File |
| --- | --- | --- |
| age key pair | | `~/.config/sops/age/keys.txt` on your machine. Never in Git |
| Secret | `flux-system/sops-age` | By hand only: it's the key to everything else |
| SOPS rules | | `.sops.yaml` at the repo root |
| Kustomization | `secrets` | `clusters/dev/secrets.yaml` |
| Secret, encrypted | `external-dns/externaldns-tsig` | `secrets/local/external-dns-tsig.yaml` |
| Secret, encrypted | `cert-manager/local-ca` | `secrets/local/cert-manager-local-ca.yaml` |

## Tasks

1. A key pair:
   ```sh
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```
   It prints the public key (`age1...`). Back the file up somewhere safe: lose
   it and nothing in Git can be decrypted. sops looks there by default on
   Linux; on macOS set `SOPS_AGE_KEY_FILE` to it.
2. Give Flux the private key:
   ```sh
   kubectl --context k3d-dev -n flux-system create secret generic sops-age \
     --from-file=age.agekey="$HOME/.config/sops/age/keys.txt"
   ```
3. Tell sops what to encrypt, at the repo root:
   ```yaml
   # .sops.yaml
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       encrypted_regex: ^(data|stringData)$
       age: age1...   # your public key
   ```
4. The TSIG Secret as a file, encrypted before it's ever staged:
   ```sh
   mkdir -p secrets/local
   kubectl --context k3d-dev -n external-dns create secret generic externaldns-tsig \
     --from-literal=secret="$(kubectl --context k3d-dev -n dns get secret externaldns-tsig \
       -o jsonpath='{.data.secret}' | base64 -d)" \
     --dry-run=client -o yaml > secrets/local/external-dns-tsig.yaml
   sops --encrypt --in-place secrets/local/external-dns-tsig.yaml
   ```
   Run sops from the repo root so `.sops.yaml` is found. Open the file: `data`
   is ciphertext, `metadata` is readable.
5. The Kustomization that decrypts:
   ```yaml
   # clusters/dev/secrets.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: secrets
     namespace: flux-system
   spec:
     dependsOn:
       - name: infra-base          # the namespaces
     interval: 10m
     sourceRef:
       kind: GitRepository
       name: flux-system
     path: ./secrets/local
     prune: true
     decryption:
       provider: sops
       secretRef:
         name: sops-age
   ```
6. `git add .sops.yaml clusters/dev/secrets.yaml secrets/`, commit, push.
   k9s `:secrets -n external-dns`, `x` on `externaldns-tsig`: the plain value,
   and the same as BIND's. Flux took over the hand-made Secret.
7. The CA the same way: `kubectl --context k3d-dev -n cert-manager create secret tls local-ca --cert ... --key
   ... --dry-run=client -o yaml` into `secrets/local/cert-manager-local-ca.yaml`,
   then `sops --encrypt --in-place`.

## Done when

- `git grep` finds no plaintext secret, and a rebuilt cluster gets every
  secret back from Git plus the one `sops-age` Secret.

## Where it gets hard

- Bootstrap's `flux-system` Kustomization applies everything under
  `clusters/dev/` with no decryption, so an encrypted file there fails to
  apply. That's why secrets live under `secrets/`.
- `sops-age` can't be in Git. After a rebuild, recreate it (task 2) before
  Flux syncs `secrets`.
- Editing: `sops secrets/local/<file>` decrypts into your editor and
  re-encrypts on save. Never decrypt to disk.
- `bootstrap.sh` generates a new TSIG key for each new cluster. After a
  rebuild, BIND has a key Git doesn't; re-run task 4 and push.

## Links

- <https://fluxcd.io/flux/guides/mozilla-sops/>
- <https://github.com/getsops/sops>
