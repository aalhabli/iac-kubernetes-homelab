# Layered 3-2-1 Backup Strategy (Velero + Longhorn + PBS + restic → MinIO)

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
The lab holds data of very different shapes and very different value: irreplaceable personal photos (Immich), documents (Paperless), application databases, the Kubernetes cluster state itself, and the VM/LXC images that everything runs on. Longhorn replication ([ADR-0008](adr-0008-longhorn-storage.md)) is *not* a backup — all replicas currently sit on the one 2 TB laptop NVMe, so a disk failure, a fat-fingered delete, a bad ArgoCD sync, or ransomware would take the live data and every replica together. We need a real backup strategy that protects each data shape with the right tool and gets copies *off* the primary host.

## Alternatives Considered
* **Longhorn snapshots only:** Snapshots living on the same disk as the data.
* **A single tool for everything** (e.g., just restic, or just Velero).
* **Sync-based copy** (e.g., Syncthing mirroring data to the workstation).
* **A layered 3-2-1 strategy** — a purpose-built tool per data shape, copies on independent media, off-site planned.

## Decision
We will implement a **layered 3-2-1 backup strategy**: at least **3 copies** of data, on at least **2 different media/devices**, with **1 off-site** — each data shape protected by the tool built for it, all converging on a **MinIO (S3-compatible) target running on the workstation's 8 TB NVMe**.

| Data shape | Tool | Target |
|---|---|---|
| **Kubernetes cluster state** (resources, etcd) | **Velero** | MinIO (S3) on 8 TB |
| **Persistent volume data** (app PVs) | **Longhorn** scheduled backups | MinIO (S3) on 8 TB |
| **VM / LXC images** | **Proxmox Backup Server (PBS)** | 8 TB (PBS datastore) |
| **Loose file data** (e.g., document trees) | **restic** | MinIO (S3) on 8 TB |

**3-2-1 accounting (current → planned):**
* **Copy 1** — live data on the laptop 2 TB NVMe (Longhorn).
* **Copy 2** — backups on the workstation 8 TB NVMe via MinIO/PBS (**different device, different host**).
* **Copy 3 / off-site** — **deferred**: a cloud S3 target (Backblaze B2 or Cloudflare R2) is the documented *slot*, to be filled in a later phase. The future Synology NAS adds a third **local** copy on **spinning disks** (a genuinely different medium from NVMe) ahead of, or alongside, the cloud copy.

### Rationale
* **Defense in depth by data shape.** No single tool backs up everything *well*. Velero understands Kubernetes objects; Longhorn understands its own volumes and can snapshot them consistently; PBS does deduplicated, incremental VM/LXC images at the hypervisor; restic does encrypted, deduplicated file backup. Matching tool to data shape is the [ADR-0003](adr-0003-workload-placement.md) "right tool for the job" principle applied to recovery.
* **One S3 endpoint, many tools.** Velero requires object storage, Longhorn supports it, and restic speaks it — so a single **MinIO** instance on the 8 TB serves all three, instead of three different target types to operate ([ADR-0008](adr-0008-longhorn-storage.md) storage tiering).
* **Off-host is the whole point.** Because Longhorn's replicas all live on the one NVMe today, the 8 TB copy on a *separate physical machine* is what turns "redundancy" into "recoverability after losing the laptop." It satisfies "different media/device" now; the NAS and cloud extend it to full 3-2-1.
* **Immutability defeats the scary failure modes.** Object storage (MinIO, and later cloud) supports versioning/object-lock, so a corruption, deletion, or ransomware event can't overwrite older good snapshots — exactly what a sync mirror cannot promise.
* **The intermittent target is fine for backups.** The workstation isn't always on, but scheduled backup jobs simply fail and **succeed on the next run** when it returns — periodic-with-retry is the correct model for point-in-time backups (no continuous mirror needed).
* **Rejection of snapshots-only:** A snapshot on the same failing disk dies with it; it's a convenience, not protection.
* **Rejection of one-tool-for-everything:** Forces a tool to back up data it doesn't understand (e.g., restic copying a live database's files yields a torn, inconsistent backup).
* **Rejection of sync-based copy:** Sync is not backup — it propagates deletes and corruption and keeps no point-in-time history (see Syncthing's actual role: file sync, not recovery).

## Consequences

### Positive (What becomes easier?)
* **Recoverable from realistic disasters:** disk loss, bad sync, accidental delete, ransomware, or a wiped host — each has a restore path, and a DR runbook will exercise them.
* **A clean DR bootstrap story:** rebuild Proxmox from PBS, re-bootstrap k3s + ArgoCD ([ADR-0005](adr-0005-argocd-vs-flux.md)), restore PV data from Longhorn/Velero — Git plus backups fully reconstitute the lab.
* **One backup target** (MinIO) to operate for the cloud-native layers, with PBS handling the hypervisor layer it's purpose-built for.

### Negative (What becomes harder/Risks?)
* **Off-site is not yet in place.** Until the cloud slot is filled (or the NAS is off-premises capable), a single-site disaster (fire/theft affecting both machines) is unprotected. This is a **known, accepted, time-boxed gap**, tracked as a roadmap follow-up — not an oversight.
* **Restore testing is real work.** Backups that have never been restored are wishful thinking; the strategy is only honored if the DR runbook is periodically *executed*, not just written.
* **Several tools to learn and operate.** Velero, Longhorn backups, PBS, and restic each have their own configuration and failure modes — accepted, since recovery is exactly where homogeneity is dangerous and learning is valuable.
* **Backups can silently fall behind** while the workstation is off. We mitigate with monitoring/alerting on last-successful-backup age so a long-offline target surfaces as an alert rather than a surprise at restore time.
* **Backup credentials** (MinIO keys, restic repo password, the future cloud token) are themselves secrets — managed via 1Password + ESO ([ADR-0006](adr-0006-secrets-management.md)) and, critically, the restic password must also be stored *off* the cluster so backups are restorable when the cluster is gone.
