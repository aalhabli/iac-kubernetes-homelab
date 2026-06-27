# Use OpenTofu over Terraform for Infrastructure Provisioning

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
We need to provision Proxmox VMs and LXC containers ([ADR-0001](adr-0001-proxmox-hypervisor.md)) declaratively rather than clicking through the Proxmox web UI. The infrastructure must be reproducible: a wiped host should be rebuildable from code. The dominant tool for this is Terraform/HCL, but HashiCorp's August 2023 relicensing of Terraform from the open-source MPL 2.0 to the source-available Business Source License (BSL) changed the landscape and forces a deliberate choice rather than reaching for the default.

## Alternatives Considered
* **HashiCorp Terraform (BSL):** The incumbent standard, now under a non-open-source license.
* **Pulumi:** Infrastructure as *actual code* (TypeScript/Python/Go) instead of HCL.
* **Ansible alone:** Use Ansible's Proxmox modules to create the VMs as well as configure them.
* **Proxmox web UI / `qm` + `pct` shell scripts:** Imperative, manual provisioning.

## Decision
We will use **OpenTofu** with the community **`bpg/proxmox`** provider to provision all VMs and LXC containers, sourcing them from cloud-init templates.

### Rationale
* **Open-source license alignment.** OpenTofu is the Linux Foundation fork of Terraform, created in direct response to the BSL change, and remains MPL 2.0. This repo's first guiding principle is "everything is declarative and in Git" with an open-source ethos; building on a tool whose license could restrict how I run my own lab tomorrow contradicts that on principle.
* **Drop-in compatibility.** OpenTofu maintains HCL and state compatibility with Terraform. The configurations, modules, and mental models are 1:1 transferable in either direction, so choosing the open fork costs nothing in practice and keeps me current with where the ecosystem is actually heading.
* **Declarative state and plan/apply workflow.** `tofu plan` shows a reviewable diff of what will change before it changes — exactly the "documented decisions over undocumented cleverness" we want, and a natural fit for a CI gate (`tofu plan` on PRs).
* **Rejection of Pulumi:** Real-language IaC is powerful but introduces a general-purpose runtime (and its failure modes) into the provisioning layer. HCL's constrained, declarative surface is a feature here.
* **Rejection of Ansible-for-provisioning:** Ansible is excellent at *configuring* a host that already exists but is procedural and weak at *lifecycle state* (knowing a VM exists and reconciling drift). We keep a clean seam: **OpenTofu creates, Ansible configures** (see roadmap Phase 1).
* **Rejection of manual/`qm`:** Click-ops and one-off scripts are precisely the anti-pattern this lab is built to avoid.

## Consequences

### Positive (What becomes easier?)
* Infrastructure is **reproducible and reviewable** — a `tofu plan` diff is the change-control record for the physical-ish layer.
* Clean separation of concerns: provisioning (OpenTofu) vs. configuration (Ansible) vs. workloads (Kubernetes/ArgoCD).
* The full VM/LXC topology lives in version control, so a catastrophic host failure is a rebuild, not an archaeology project.

### Negative (What becomes harder/Risks?)
* **State file contains secrets in plaintext.** The `.tfstate` is sensitive (it can hold generated passwords, tokens). It is already git-ignored; we must additionally choose a state backend and keep it off public surfaces. `*.tfvars` (API keys) are likewise ignored.
* **Smaller registry/ecosystem than Terraform.** A handful of providers/modules publish to the Terraform Registry first; OpenTofu's registry generally mirrors them, but occasional lag or divergence is possible.
* **Provider maturity.** The `bpg/proxmox` provider is community-maintained; we accept tracking its release notes and pinning versions to avoid breaking changes against the Proxmox API.
