# Use Longhorn for Replicated Kubernetes Persistent Storage

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
Stateful workloads — Paperless-ngx, Immich, the monitoring stack's TSDB, application databases — need persistent volumes that survive pod rescheduling and, ideally, the loss of a node. We must choose a `StorageClass` for the 3-node k3s cluster ([ADR-0002](adr-0002-k3s-vs-talos.md)). The available disks shape this decision heavily: the cluster runs as Proxmox VMs on the laptop's single **2 TB NVMe** (the only always-on disk); a workstation holds an **8 TB NVMe** but is **not always on**; a Synology NAS is a future purchase. Only the laptop NVMe can host live, always-available storage — so the *primary* storage class must live there, and the other disks serve backup/cold tiers ([ADR-0009](adr-0009-backup-strategy.md)).

## Alternatives Considered
* **k3s default `local-path` provisioner:** Volumes are a directory on whichever node the pod lands on.
* **NFS** from the workstation 8 TB or a future NAS.
* **Rook/Ceph:** Full distributed storage system; the CNCF heavyweight.
* **Longhorn:** Rancher's lightweight distributed block storage for Kubernetes.
* **democratic-csi / ZFS-over-iSCSI** backed by Proxmox storage.

## Decision
We will use **Longhorn** as the default `StorageClass`, providing replicated block-mode persistent volumes across the cluster nodes, all backed by the laptop's 2 TB NVMe.

### Rationale
* **Replicated volumes = node-failure survival.** Longhorn synchronously replicates each volume across nodes. If a k3s VM dies or is rebuilt, the volume's data survives on the others and the pod reschedules intact. `local-path` cannot do this — a pod that moves nodes loses its data — which disqualifies it for anything stateful we care about.
* **Snapshots and built-in backup to S3/NFS.** Longhorn does volume snapshots and scheduled backups to an S3-compatible target (our MinIO on the 8 TB — see [ADR-0009](adr-0009-backup-strategy.md)). This is the foundation of the k8s layer of the 3-2-1 strategy. Immich's irreplaceable photos make this non-negotiable.
* **Right-sized for a 3-node homelab.** Longhorn installs as pods + a CSI driver with a clear UI, purpose-built for exactly this scale. Rook/Ceph is far more capable but far heavier — it wants dedicated disks/nodes and a large memory budget, a poor trade for a single-host, 3-VM lab.
* **Block semantics + visibility for learning.** Longhorn presents real block devices (good for databases) and a dashboard that makes replica placement, rebuilds, and snapshots *visible* — valuable for deliberately learning how distributed storage behaves.
* **The intermittent 8 TB can't be live storage.** Longhorn marks replicas on an unreachable node as failed and triggers rebuilds; a workstation that powers off would cause constant churn. So the 8 TB is deliberately *not* a Longhorn node — it serves as a backup target instead, and the future always-on NAS becomes the path to a proper cold/bulk NFS tier.
* **Rejection of `local-path`:** No replication, HA, or backup — fine only for scratch/cache.
* **Rejection of NFS as primary:** A single NFS server is a SPOF and gives file, not block, semantics (awkward for databases). It is, however, the right shape for a *backup target* and for cold bulk media on the future NAS — not for primary RWO volumes.
* **Rejection of Rook/Ceph:** Too heavy for the hardware; its overhead would starve the actual workloads.
* **Rejection of democratic-csi/ZFS:** Pushes storage onto the Proxmox host and adds iSCSI plumbing without the in-cluster replication and UX Longhorn provides.

## Consequences

### Positive (What becomes easier?)
* **HA persistent volumes** that survive a node/VM failure, enabling genuine self-healing for stateful apps.
* **Snapshots + scheduled backups to MinIO** built in, feeding the backup strategy directly.
* **A clear `StorageClass` story:** Longhorn (replicated) for anything that matters; `local-path` available for ephemeral/scratch.

### Negative (What becomes harder/Risks?)
* **All replicas share one physical disk — today.** Because the 3 k3s nodes are VMs on the single 2 TB NVMe, Longhorn replication protects against VM/OS failure and corruption but **not** against physical disk loss. This is the central reason off-host backups ([ADR-0009](adr-0009-backup-strategy.md)) are mandatory: **replication is not a backup.** A genuine multi-disk spread waits on the future NAS or added physical disks.
* **Storage amplification under a 2 TB ceiling.** 3× replication turns a 100 GB volume into ~300 GB. With Immich in the mix, capacity planning is real — some volumes may run at replica count 2, and large cold media is a candidate to move to an NFS tier on the NAS once it exists.
* **Node prerequisites.** Longhorn needs `open-iscsi` and related utilities on every node — handled by the Ansible base role (the OpenTofu-creates / Ansible-configures seam from [ADR-0004](adr-0004-opentofu-vs-terraform.md)).
* **Overhead.** Replication and the Longhorn control plane consume RAM/CPU and add write latency versus raw local NVMe — an accepted cost for durability on the 64 GB budget.
