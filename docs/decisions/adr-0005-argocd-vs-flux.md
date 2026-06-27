# Use ArgoCD with the App-of-Apps Pattern over Flux for GitOps

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
Once k3s is running ([ADR-0002](adr-0002-k3s-vs-talos.md)), we need a mechanism to deploy and continuously reconcile workloads from Git. The project's second guiding principle is that **a push to `main` is the only way to change the cluster** — no `kubectl apply` from a laptop. This is the definition of GitOps, and it requires a controller running *inside* the cluster that pulls desired state from Git and reconciles the live state to match. We must choose that controller and the pattern for organizing what it manages.

## Alternatives Considered
* **Flux CD:** A CNCF-graduated, controller-based GitOps toolkit; lightweight, no built-in UI.
* **CI-driven push (GitHub Actions running `kubectl`/`helm`):** Pipeline pushes manifests to the cluster.
* **Manual `kubectl apply` / `helmfile`:** Imperative application of manifests.
* **Rancher Fleet:** GitOps built into the Rancher ecosystem.

## Decision
We will use **ArgoCD** as the GitOps controller, organized with the **app-of-apps** pattern: a single root `Application` points at a directory of child `Application`s, which in turn deploy the infrastructure components and apps.

### Rationale
* **Pull-based, not push-based.** ArgoCD runs inside the cluster and pulls from Git. The cluster's credentials never leave the cluster, and CI never needs cluster-admin — a materially better security posture than a pipeline holding a kubeconfig (this is GitOps proper, and the reason CI-push is rejected).
* **The dashboard is a genuine learning multiplier.** ArgoCD's UI renders the live application graph, sync/health status, and live-vs-desired diffs. For someone deliberately learning Kubernetes deeply, *seeing* the reconciliation — which resource is OutOfSync and why — collapses the feedback loop dramatically. Flux is excellent but deliberately headless; the visibility is worth ArgoCD's heavier footprint here.
* **App-of-apps gives a single bootstrap entry point.** One root Application, committed once, recursively brings up the entire platform. Disaster recovery becomes: install ArgoCD, apply the root app, walk away. This pairs directly with the backup/DR strategy ([ADR-0009](adr-0009-backup-strategy.md)).
* **ApplicationSets for scale.** As apps multiply, ApplicationSets template them from a single generator, avoiding copy-paste sprawl.
* **Rejection of Flux:** A close call and a defensible alternative. Flux is lighter and arguably more "GitOps-purist," but its lack of a first-class UI makes the early learning curve steeper, and ArgoCD's app-of-apps maps more intuitively onto a phased, layered platform.
* **Rejection of CI-push:** Inverts the trust model (CI holds cluster creds), drifts silently when someone changes the cluster out-of-band, and lacks continuous reconciliation.
* **Rejection of Fleet:** Tightly coupled to the Rancher ecosystem we are otherwise not adopting.

## Consequences

### Positive (What becomes easier?)
* **Git is the single source of truth.** The live cluster is, by construction, whatever `main` says it is; drift is detected and (optionally) auto-healed.
* **Self-documenting topology.** The app-of-apps tree *is* the architecture diagram of what's deployed.
* **One-command DR bootstrap** of the entire workload layer.

### Negative (What becomes harder/Risks?)
* **Resource overhead.** ArgoCD (repo-server, application-controller, redis, server) is heavier than Flux's controllers. Acceptable given the 64 GB budget, but it is real RAM the apps don't get.
* **CRD and concept surface.** `Application`, `ApplicationSet`, projects, sync waves, and hooks are a non-trivial learning curve — accepted deliberately, since learning is a goal.
* **Secret bootstrapping is a chicken-and-egg.** ArgoCD must be able to decrypt SOPS-encrypted secrets at sync time, which requires the External Secrets Operator and its bootstrap token to come up first (managed with ArgoCD sync waves) — see [ADR-0006](adr-0006-secrets-management.md).
