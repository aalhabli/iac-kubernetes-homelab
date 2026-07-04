# Proxmox Backup Server (PBS) Configuration

This document serves as the static reference for how the Proxmox Backup Server (PBS) is configured and connected to the primary Proxmox Virtual Environment (PVE) host. 

## Connection Details

The PBS instance runs alongside the cluster, providing dedicated, deduplicated backups for VMs and LXCs.

- **IP Address:** `192.168.1.4`
- **Username:** `root@pam`
- **Datastore Name:** `homelab-backup`
- **Repository:** `192.168.1.4:homelab-backup`

## PVE Storage Integration

PBS is attached to the Proxmox Datacenter as a dedicated storage target:

- **Storage ID:** `pbs-local`
- **Type:** Proxmox Backup Server
- **Content Type:** Backup
- **Shared:** Yes

## Backup Job Configuration

A scheduled backup job runs automatically to ensure workloads are protected. 

- **Schedule:** Daily at `02:00`
- **Storage Target:** `pbs-local`
- **Selection Mode:** `Include selected VMs`
  - *Note:* Specific workloads are selected for backup (e.g., `pihole` LXC 100). The PBS VM itself (VM 101) is explicitly **excluded** to prevent recursive backup loops.
- **Mode:** `Snapshot` (ensures zero-downtime backups)
- **Compression:** `ZSTD (fast and good)`

## Datastore Retention (To Do)
*Define the prune/retention policies here once configured (e.g., Keep Last: 7, Keep Daily: 7, Keep Weekly: 4).*
