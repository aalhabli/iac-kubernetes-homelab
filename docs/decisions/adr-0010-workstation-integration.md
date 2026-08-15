# Workstation Integrated Over Tailscale Across a Separate NAT

* Status: Superseded by [ADR-0011](adr-0011-flat-l2-network.md)
* Date: 2026-07-05
* Superseded: 2026-08-15

> **Superseded.** The network constraint this ADR was written against no longer exists. A dedicated switch now puts the workstation and the homelab host on one L2 segment, so the cluster reaches MinIO and vLLM over the LAN. Tailscale is retained for off-network access only. See [ADR-0011](adr-0011-flat-l2-network.md). The record below is kept unchanged as the decision that was made at the time.

## Context and Problem Statement
Two of the lab's roles live on the RTX 4090 workstation rather than the ThinkPad homelab server: the 8 TB MinIO backup target ([ADR-0009](adr-0009-backup-strategy.md)) and GPU inference (vLLM, and possibly image generation later). The workstation is a **separate physical machine from the homelab server**. It is on **WiFi behind a different NAT**, while the homelab server is on **ethernet behind another NAT**; the two are not on the same L2 segment. Converting the TP-Link router to an AP/bridge to flatten them onto one subnet is not an option. The cluster nevertheless needs to reach the workstation reliably — to write Longhorn/Velero/restic backups to MinIO, and for in-cluster apps (Open WebUI, n8n) to call the vLLM API — without opening inbound ports or exposing either service to the LAN or the internet.

## Alternatives Considered
* **Flatten the network** — bridge the router / put both machines on one subnet. Ruled out by the hardware constraint.
* **Port-forward MinIO and vLLM** through the workstation's router to the homelab. Opens inbound ports, exposes services, and depends on fragile double-NAT hairpinning.
* **Move the 8 TB disk and/or GPU into the homelab server.** Defeats the point — the GPU and bulk disk are deliberately on the workstation, which is also used as a desktop.
* **Reach the workstation over Tailscale**, the same private overlay already chosen for admin/private access ([ADR-0007](adr-0007-cloudflare-tunnel.md)).

## Decision
The workstation **joins the Tailnet**, and the cluster reaches both MinIO and vLLM **over Tailscale** — by Tailscale IP / MagicDNS name, never the LAN IP. Both services bind to the Tailscale interface and are scoped by Tailnet ACLs so only the cluster and admin can reach them; neither is exposed on the LAN or publicly.

This makes **Tailscale a hard dependency of the backup path and the AI path**, which is why it is built in Phase 3 (minimum platform) alongside Longhorn, and why the Longhorn→MinIO backup wiring is pulled forward into Phase 3 rather than left with the rest of the backup work.

### Rationale
* **The overlay crosses NATs by design.** Tailscale (WireGuard) establishes connectivity between peers on different NATs without inbound port-forwarding — exactly the problem here — so no router changes are needed on either side.
* **One transport, reused.** Tailscale is already the private/admin tier ([ADR-0007](adr-0007-cloudflare-tunnel.md)); using it for the workstation avoids introducing a second remote-access mechanism.
* **No new attack surface.** Nothing is published to the LAN or internet; the services are reachable only within the Tailnet and only by the identities the ACLs allow.
* **The intermittent target model still holds.** The workstation is not always on; scheduled backups fail and succeed on the next run ([ADR-0009](adr-0009-backup-strategy.md)), and GPU workloads simply queue or error when it is off. Tailscale changes the transport, not that model.

## Consequences

### Positive (What becomes easier?)
* **The 8 TB disk and the RTX 4090 stay where they belong** (the workstation) while still serving the cluster.
* **No router surgery and no open ports** — the constraint that AP-bridging is off the table is met head-on.
* **A single private overlay** carries admin access, Immich, backups, and AI, all under one ACL model.

### Negative (What becomes harder / Risks?)
* **Tailscale is now on the critical path for recovery.** Backups ride the overlay, so the Tailnet (and its auth) must be part of the DR runbook — restoring must not silently depend on a service that is itself down. Auth keys are managed via 1Password + ESO ([ADR-0006](adr-0006-secrets-management.md)), with the recovery path documented off-cluster.
* **Overlay throughput and latency** are lower than raw LAN. Acceptable for periodic backups and API-shaped inference calls; large restores will be slower than a wired copy would be.
* **Two failure domains to reason about.** The workstation's WiFi link and NAT are outside the homelab's control; monitoring on last-successful-backup age ([ADR-0009](adr-0009-backup-strategy.md)) surfaces a long-offline workstation rather than letting it pass unnoticed.
