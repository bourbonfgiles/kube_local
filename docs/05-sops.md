# 5. Secrets in Git with SOPS

> You end up with: the TSIG and CA Secrets stored encrypted in this public
> repo, and Flux decrypting them into the cluster.

## What it is

SOPS encrypts the *values* in a YAML file and leaves the keys readable, so a
Secret in Git still shows its name, namespace and field names, and diffs stay
meaningful. It encrypts to one or more keys: here an **age** key pair, a
modern replacement for GPG keys.

```mermaid
flowchart LR
  you["You: sops --encrypt<br/>with the age public key"] --> git["Git<br/>data: ENC[AES256_GCM,...]"]
  git --> kc["kustomize-controller<br/>decryption: sops"]
  key["Secret sops-age<br/>age private key"] --> kc
  kc --> sec["Secret in the cluster<br/>plain values"]
```

| Piece | Lives | Note |
| --- | --- | --- |
| age public key | `.sops.yaml` in the repo | Anyone can encrypt with it |
| age private key | `~/.config/sops/age/keys.txt`, and Secret `flux-system/sops-age` | The one thing never in Git |
| `.sops.yaml` | Repo root | Which files to encrypt, which fields, to which keys |
| Encrypted Secret | `secrets/local/*.yaml` | Safe to commit |

Flux decrypts at apply time, in memory. The plaintext only ever exists in the
cluster's Secret.

## On EKS

SOPS with an AWS KMS key instead of age: `.sops.yaml` names the KMS ARN, and
kustomize-controller gets an IAM role allowed to decrypt with it. Nothing to
copy into the cluster by hand. The other common choice is External Secrets
Operator reading AWS Secrets Manager, so secrets never touch Git at all.

## Requirements

**In the cluster**: Flux (lesson 2). The hand-made Secrets
`external-dns/externaldns-tsig` (lesson 3) and `cert-manager/local-ca`
(lesson 4), if you did those lessons.

**On your machine**: `sops`, `age` and `age-keygen` (comes with `age`),
`kubectl`, `flux`, `git`, and `sofka` or `k9s` ([lesson 0](00-tools.md)).

## Install by hand

### 1. A key pair

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

It prints the public key (`age1...`). sops finds the private key at that path
on Linux; on macOS set `SOPS_AGE_KEY_FILE` to it.

> [!CAUTION]
> Back `keys.txt` up somewhere outside this machine. Lose it and nothing in
> Git can be decrypted.

### 2. Encrypt, read, apply

A throwaway Secret to see what SOPS does:

```sh
mkdir -p scratch/05
kubectl --context k3d-dev -n default create secret generic demo \
  --from-literal=password=hunter2 --dry-run=client -o yaml > scratch/05/demo.yaml
sops --encrypt --age "$(age-keygen -y ~/.config/sops/age/keys.txt)" --encrypted-regex '^(data|stringData)$' --in-place scratch/05/demo.yaml
cat scratch/05/demo.yaml
```

`data.password` is ciphertext; `metadata` is readable; a `sops:` block at the
end records how to decrypt it. Now apply it the way Flux will, decrypting in
a pipe so the plaintext never touches disk:

```sh
sops --decrypt scratch/05/demo.yaml | kubectl --context k3d-dev apply -f -
```

```sh
kubectl --context k3d-dev -n default get secret demo -o jsonpath='{.data.password}' | base64 -d
```

`hunter2`.

sofka / k9s: `:secrets -n default`, `x` on `demo`

### 3. Iterate

#### 1. Edit it encrypted

```sh
sops scratch/05/demo.yaml
```

It opens decrypted in your editor and re-encrypts on save. `data` holds
base64, as in any Secret.

#### 2. What a change looks like in Git

Keep a copy, set a new password, and compare:

```sh
cp scratch/05/demo.yaml scratch/05/demo.before.yaml
sops set scratch/05/demo.yaml '["data"]["password"]' "\"$(printf hunter3 | base64)\""
git diff --no-index scratch/05/demo.before.yaml scratch/05/demo.yaml
```

Only that value's ciphertext and the `sops.mac` change.

#### 3. Encrypt everything

A fresh copy without `--encrypted-regex`:

```sh
kubectl --context k3d-dev -n default create secret generic demo-all \
  --from-literal=password=hunter2 --dry-run=client -o yaml > scratch/05/demo-all.yaml
sops --encrypt --age "$(age-keygen -y ~/.config/sops/age/keys.txt)" --in-place scratch/05/demo-all.yaml
cat scratch/05/demo-all.yaml
sops --decrypt scratch/05/demo-all.yaml | kubectl --context k3d-dev apply -f - --dry-run=server
kubectl --context k3d-dev apply -f scratch/05/demo-all.yaml --dry-run=server
```

Every value is encrypted, even `metadata.name`. Decrypted, it applies; as
committed, Kubernetes rejects it.

#### 4. A machine without the key

```sh
mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.aside
sops --decrypt scratch/05/demo.yaml
mv ~/.config/sops/age/keys.txt.aside ~/.config/sops/age/keys.txt
sops --decrypt scratch/05/demo.yaml
```

The first `--decrypt` fails as it would anywhere without the key; the second
works again.

### 4. Clean up

```sh
kubectl --context k3d-dev -n default delete secret demo
```

## Install with Flux

| Kind | Name | File |
| --- | --- | --- |
| SOPS rules | | `.sops.yaml` |
| Secret | `flux-system/sops-age` | By hand only: it's the key to everything else |
| Kustomization | `secrets` | `clusters/dev/secrets.yaml` |
| Secret, encrypted | `external-dns/externaldns-tsig` | `secrets/local/external-dns-tsig.yaml` |
| Secret, encrypted | `cert-manager/local-ca` | `secrets/local/cert-manager-local-ca.yaml` |

1. Rules, so you don't pass flags each time:

   **Write `.sops.yaml`**
   ```yaml
   # .sops.yaml
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       encrypted_regex: ^(data|stringData)$
       age: age1...   # yours: age-keygen -y ~/.config/sops/age/keys.txt
   ```

2. Give Flux the private key:
   ```sh
   kubectl --context k3d-dev -n flux-system create secret generic sops-age \
     --from-file=age.agekey="$HOME/.config/sops/age/keys.txt"
   ```
3. The TSIG Secret as a file, encrypted before it's staged. Run sops from the
   repo root so `.sops.yaml` is found:
   ```sh
   mkdir -p secrets/local
   kubectl --context k3d-dev -n external-dns create secret generic externaldns-tsig \
     --from-literal=secret="$(kubectl --context k3d-dev -n dns get secret externaldns-tsig \
       -o jsonpath='{.data.secret}' | base64 -d)" \
     --dry-run=client -o yaml > secrets/local/external-dns-tsig.yaml
   sops --encrypt --in-place secrets/local/external-dns-tsig.yaml
   ```
4. The CA the same way:
   ```sh
   kubectl --context k3d-dev -n cert-manager create secret tls local-ca \
     --cert="$(mkcert -CAROOT)/rootCA.pem" --key="$(mkcert -CAROOT)/rootCA-key.pem" \
     --dry-run=client -o yaml > secrets/local/cert-manager-local-ca.yaml
   sops --encrypt --in-place secrets/local/cert-manager-local-ca.yaml
   ```
5. The Kustomization that decrypts:

   **Write `clusters/dev/secrets.yaml`**
   ```yaml
   # clusters/dev/secrets.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: secrets
     namespace: flux-system
   spec:
     dependsOn:
       - name: infra-base          # creates the namespaces
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

6. Commit, push, and look:
   ```sh
   git add .sops.yaml clusters/dev/secrets.yaml secrets/
   git commit -m "Encrypted secrets with SOPS"
   git push
   flux --context k3d-dev reconcile kustomization flux-system --with-source
   kubectl --context k3d-dev -n flux-system get kustomization secrets
   kubectl --context k3d-dev -n external-dns get secret externaldns-tsig -o yaml
   ```
   `secrets` is `Ready`, and the Secret's value matches BIND's. Its
   `kustomize.toolkit.fluxcd.io` labels show Flux has taken over the Secret
   you made by hand.

   sofka / k9s: `:kustomizations -n flux-system`, then
   `:secrets -n external-dns`, `x`. Who owns it: sofka `:gitops` on the
   Secret; k9s `Shift-q` (dotfiles plugin).

## Exercises

1. `git grep -nE 'hunter2|BEGIN (RSA |EC )?PRIVATE'` the whole repo: nothing.
2. Edit the TSIG Secret with `sops secrets/local/external-dns-tsig.yaml`, push,
   and watch ExternalDNS's updates start failing. Put it back.
3. Rebuild the cluster. Recreate `sops-age` (step 2) before Flux syncs
   `secrets`, and see everything else come back on its own.
4. Harder: add a second age recipient (a key for "CI") to `.sops.yaml`, then
   `sops updatekeys` each file. Prove either key alone can decrypt.

## Where it gets hard

- `flux-system` applies everything under `clusters/dev/` with no decryption,
  so an encrypted file there fails to apply. Secrets live under `secrets/`.
- `sops-age` is the one Secret recreated by hand after every rebuild. Until it
  exists, `secrets` fails with a decryption error:
  `kubectl --context k3d-dev -n flux-system describe kustomization secrets`
  shows it. In sofka or k9s, `ctrl-z` on `:kustomizations -A`; sofka's `X`
  gives the message ([lesson 0](00-tools.md)).
- `bootstrap.sh` generates a new TSIG key for each new cluster. After a
  rebuild BIND has a key Git doesn't; redo step 3 and push.
- `sops --encrypt` on a file that's already encrypted fails; `sops` (edit) is
  for changing one.

## Links

- <https://fluxcd.io/flux/guides/mozilla-sops/>
- <https://github.com/getsops/sops>
- <https://github.com/FiloSottile/age>
