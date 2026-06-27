# Use 1Password + External Secrets Operator for Secrets, with a Minimal SOPS+age Bootstrap Tier

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
GitOps ([ADR-0005](adr-0005-argocd-vs-flux.md)) demands that the desired state of the cluster — *including secrets* — be reconcilable from Git, so ArgoCD can stand the platform up from nothing. But secrets (API tokens, database passwords, the Cloudflare token, TLS keys) cannot sit in a public repo in plaintext, and base64 Kubernetes Secrets are encoding, not encryption. We need a secrets architecture that keeps nothing sensitive in Git in the clear, is recoverable in a disaster, and — critically — does not reintroduce the bootstrap-dependency trap from [ADR-0003](adr-0003-workload-placement.md), where the cluster needs a service to be alive in order to come alive.

## Alternatives Considered
* **Plain Kubernetes Secrets in Git:** base64 is not encryption — a non-starter for a public repo.
* **SOPS + age (everything):** File-level encryption; encrypted secrets committed to Git, decrypted at apply time.
* **Bitnami Sealed Secrets:** A controller encrypts to a cluster-held key; only that cluster can decrypt.
* **Self-hosted Vaultwarden/Bitwarden as the cluster backend:** Run my own password manager and sync from it.
* **HashiCorp Vault + ESO:** A full secrets platform with dynamic secrets and leasing.
* **1Password + External Secrets Operator (ESO):** 1Password as source of truth; ESO syncs items into native k8s Secrets.

## Decision
We will use **1Password as the source of truth for secrets, synced into the cluster by the External Secrets Operator (ESO) via the 1Password SDK provider** (a service-account token; no self-hosted Connect server). Git contains only `ExternalSecret` *references* — vault/item/field — never ciphertext or plaintext.

A **minimal SOPS+age tier** exists for exactly one purpose: to commit the single 1Password service-account token to Git, encrypted, so that even the bootstrap step is GitOps-able. Everything operational flows from 1Password.

```
Git:  ExternalSecret { ref: vault/item/field }      (no ciphertext in repo)
          │
          ▼
   [ESO in-cluster] ── service-account token ──▶ 1Password API
          │
          ▼
   native Kubernetes Secret  ──▶  consumed by pods

Bootstrap only:  SOPS+age-encrypted 1Password token  ──▶  injected once at cluster bring-up
```

### Rationale
* **1Password is already in hand and is the more enterprise pattern.** I already pay for 1Password; ESO + an external secrets manager is the production-standard architecture (more so than committing ciphertext with SOPS). Git holds only references, so the repo never contains sensitive material at all — strictly better than encrypted-blobs-in-Git.
* **ESO over the native 1Password operator.** ESO abstracts the backend behind a standard `ExternalSecret` CRD, so the secret *consumers* are vendor-neutral — I could swap 1Password for Vault later without rewriting workloads. ESO is also the CNCF-popular, broadly-applicable component to learn.
* **SDK provider over Connect.** The 1Password SDK provider authenticates with a service-account token and needs nothing self-hosted, eliminating the Connect server as a moving part and a thing to keep available.
* **The one-secret bootstrap problem, solved cleanly.** ESO can't fetch anything until it has the 1Password token — a classic chicken-and-egg. Rather than inject that token by hand on every rebuild, we keep a *tiny* SOPS+age footprint to commit just that token encrypted. This makes a from-scratch DR bootstrap fully declarative while keeping SOPS's surface (and the age-key custody burden) as small as possible.
* **Avoids the circular dependency.** App and infra secrets come from 1Password (external), and the cluster's *boot path* depends only on the manually-recoverable age key + the encrypted token — never on a self-hosted service being alive. This is the [ADR-0003](adr-0003-workload-placement.md) rule applied to secrets.
* **Rejection of SOPS-for-everything:** Workable, but it puts ciphertext for every secret in Git and makes the age key the custody point for *all* secrets, with no rotation story. Confining SOPS to one bootstrap value is far less risk.
* **Rejection of self-hosted Vaultwarden as the backend:** Creates exactly the circular dependency above (the secrets store lives in the cluster that needs it), and ESO's Bitwarden support targets the separate *Bitwarden Secrets Manager* product, whose Vaultwarden emulation is immature. Vaultwarden remains fine as a *personal* vault, just not the cluster's backbone.
* **Rejection of Vault *now*:** The eventual "big" answer, but standing up Vault before there are workloads to justify it is the premature complexity the phased roadmap exists to prevent. ESO + 1Password gives most of the benefit now; Vault can slot in behind ESO later.

## Consequences

### Positive (What becomes easier?)
* **No sensitive material in Git at all** — only references. The repo can be fully public without a secret-scanning panic.
* **Centralized rotation:** rotate a secret in 1Password and ESO re-syncs it; no re-encrypt-and-commit dance.
* **Vendor-flexible:** the `ExternalSecret` abstraction means the backend can change without touching workloads.
* **Fully declarative DR bootstrap:** the SOPS-encrypted token means `apply root app` can bring the whole secrets chain online from cold.

### Negative (What becomes harder/Risks?)
* **Two key custodies, not zero.** I must protect (a) the age private key for the bootstrap tier and (b) the 1Password service-account token's scope. The age key must be backed up out-of-band (password manager + offline copy); losing it breaks the automated bootstrap (though secrets themselves survive in 1Password).
* **External dependency for sync.** ESO needs 1Password's API reachable to (re)sync. Mitigated because ESO caches into native k8s Secrets, so running pods keep their already-synced values during a 1Password/internet outage — but *new* secrets can't be fetched until connectivity returns.
* **ArgoCD/ESO ordering.** ESO must be healthy (and its token present) before workloads that depend on synced secrets sync — managed with ArgoCD sync waves so ESO and the bootstrap secret come up first.
* **Scoping discipline.** The 1Password service account should be least-privilege (only the vaults the cluster needs), so a leaked token doesn't expose unrelated personal credentials.
