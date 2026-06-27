# Workload Placement — What Runs in Kubernetes vs. LXC/VM

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
With Proxmox ([ADR-0001](adr-0001-proxmox-hypervisor.md)) and k3s ([ADR-0002](adr-0002-k3s-vs-talos.md)) established, we have two distinct places a workload can run: directly on the hypervisor as an LXC container or VM, or inside the Kubernetes cluster. The temptation in a "Kubernetes-first" homelab is to push everything into the cluster. That instinct is wrong, and resisting it is the single most important architectural judgment in this lab. We need a *principled, written rule* for placement — not an ad-hoc, per-service gut call — because the wrong placement creates circular dependencies that make the cluster impossible to cold-start.

## Alternatives Considered
* **Everything in Kubernetes:** Run DNS, monitoring, apps — all of it — as pods. Maximally "cloud-native."
* **Everything in LXC/VMs, no Kubernetes:** Treat the lab as a classic Proxmox homelab; skip the cluster entirely.
* **Ad-hoc, decide-per-service:** No framework; place each new workload wherever feels convenient at the time.

## Decision
We will place workloads according to an explicit **bootstrap-dependency rule**:

> A service may only run *inside* Kubernetes if Kubernetes does not depend on that service in order to start.

Anything that the cluster itself needs in order to come up from cold — or that must remain available *while the cluster is down* — runs at the Proxmox layer (LXC or VM). Everything else runs in Kubernetes.

| Workload | Placement | Why |
|---|---|---|
| **PiHole / DNS** | LXC (2x for redundancy) | The cluster resolves image registries and peers by name. If DNS is a pod, a cold cluster cannot pull the DNS pod's image → deadlock. DNS is a *bootstrap dependency of* the cluster. |
| **Proxmox VE / PBS** | Host / LXC | These *are* the virtualization and backup substrate. They cannot live inside what they host. |
| **Core networking (gateway, VLAN routing)** | Host / physical | Must survive any cluster failure; it is the path packets take *to reach* the cluster. |
| **Monitoring (Prometheus, Grafana, Loki)** | Kubernetes | Observes the cluster from within; acceptable to lose when the cluster is down (we still have Proxmox metrics + node-level access). |
| **Apps (Paperless-ngx, Syncthing, web services)** | Kubernetes | Stateless or PV-backed; benefit from self-healing, GitOps, ingress, and horizontal scaling. |

### Rationale
* **Circular-dependency avoidance is non-negotiable.** The classic homelab failure mode is putting DNS (or secrets, or storage) inside the very cluster that needs DNS to boot. The result is a cluster that, once fully powered off, can never power back on without manual intervention. The bootstrap-dependency rule mechanically prevents this entire class of outage.
* **Blast-radius isolation.** When DNS and backups live outside the cluster, a botched ArgoCD sync or a corrupted etcd cannot take down name resolution for the whole house or destroy the backups that would recover it. The most critical services have the smallest, most stable surface.
* **Right tool for the job.** This is explicitly the repo's headline judgment (see the project guiding principles): Kubernetes is a workload orchestrator, not a universal runtime. A single-binary DNS resolver in a 128 MB LXC is simpler, faster, and more reliable than the same service wrapped in a Deployment, Service, PVC, and ingress.
* **Rejection of "everything in k8s":** Creates the cold-start deadlock above and wastes resources wrapping trivial services in orchestration machinery.
* **Rejection of "no Kubernetes":** Forfeits the entire learning objective and the self-healing/GitOps story that makes the rest of this repo valuable.
* **Rejection of "ad-hoc":** Undocumented placement decisions are exactly the "undocumented cleverness" this project rejects. A written rule is auditable and survives the six-month gap between when I make a decision and when I next have to reason about it.

## Consequences

### Positive (What becomes easier?)
* The cluster is **cold-start safe**: power everything off, power it back on, and it recovers without a human hand-resolving DNS or restoring backups.
* The most critical services (DNS, backups) have the **smallest blast radius** and the highest independent availability — when the cluster is on fire, the house still has working internet.
* New-workload decisions become **a 10-second checklist** ("does the cluster need this to boot?") instead of a debate.

### Negative (What becomes harder/Risks?)
* **Two control planes to operate.** We now manage workloads in both Proxmox (LXC/VM lifecycle) *and* Kubernetes (manifests/GitOps). This is deliberate — see the placement table — but it is genuine operational surface, mitigated by managing the LXC/VM layer with OpenTofu + Ansible so it is still IaC, not click-ops.
* **Redundancy is manual for the out-of-cluster tier.** Kubernetes gives us self-healing for pods for free; the PiHole LXCs do not get that, so we run two and document failover in a runbook rather than relying on a ReplicaSet.
