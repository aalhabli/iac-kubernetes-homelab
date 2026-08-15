# Flat Layer 2 Network for Workstation and Homelab

* Status: Accepted
* Date: 2026-08-15

## Context and Problem Statement
[ADR-0010](adr-0010-workstation-integration.md) was written against a network constraint that no longer exists. At the time, the ISP fiber box enforced client isolation between its LAN ports, and the workstation sat on WiFi behind the TP-Link's NAT while the Proxmox host sat on ethernet behind another. The two machines were not on the same L2 segment, so the cluster reached the MinIO backup target and the vLLM endpoint over Tailscale.

A dedicated switch now sits between the fiber box and everything else. The TP-Link, the Proxmox host, and the workstation all feed into that switch rather than being split across the fiber box's isolated ports. The workstation is on ethernet, and every homelab host is on `192.168.1.0/24`.

The fiber box (`192.168.1.1`) is the gateway and the DHCP server for that wired segment, handing out `192.168.1.50`–`192.168.1.199`. Infrastructure hosts sit below the pool as static assignments.

**The flattening covers the wired segment only.** The TP-Link was not converted to an access point. It holds a lease from the fiber box on its WAN port (`192.168.1.50`) and continues to run its own NAT for a separate `192.168.0.0/24` WiFi network. Wireless clients can reach wired hosts outbound through that NAT, and wired hosts cannot initiate a connection to a wireless client. Verified from the workstation: `192.168.0.1` is unreachable, and a trace toward it exits via the fiber box to the ISP rather than crossing into the TP-Link's LAN.

| Host | Address | Assignment |
|---|---|---|
| Fiber box (gateway, DHCP) | `192.168.1.1` | fixed |
| PiHole | `192.168.1.3` | static |
| PBS | `192.168.1.4` | static |
| Proxmox host | `192.168.1.200` | static |
| TP-Link WAN | `192.168.1.50` | DHCP lease |
| TP-Link LAN (WiFi clients) | `192.168.0.0/24` | behind its own NAT |

Measured from the workstation on 2026-08-15, with Tailscale stopped:

| Target | Address | RTT (avg) | Hops |
|---|---|---|---|
| Proxmox host | `192.168.1.200` | 0.46 ms | 1 |
| PBS | `192.168.1.4` | 0.82 ms | 1 |
| PiHole | `192.168.1.3` | 0.45 ms | 1 |

All three resolve to a directly adjacent MAC in the workstation's neighbour table, confirming one L2 segment rather than a routed path. The workstation link negotiates 1000 Mb/s full duplex. MinIO answers its health endpoint over the LAN address in 0.3 ms.

The question this ADR settles is which of Tailscale's jobs the switch retires.

## Alternatives Considered
* **Keep the Tailnet on the LAN path anyway** for consistency with ADR-0010. Adds WireGuard encapsulation and a userspace hop between two machines on the same switch, and keeps Tailscale on the disaster-recovery critical path for no remaining benefit.
* **Retire Tailscale entirely.** Removes off-network access, which the switch does nothing to replace.
* **VLAN-segment the new switch** to separate homelab, workstation, and IoT. Requires a managed switch and is a larger change than the problem currently demands.
* **Flatten the LAN path and keep Tailscale scoped to off-network access.**

## Decision
The workstation and the homelab share one L2 segment on `192.168.1.0/24`, the wired network served by the fiber box. In-home traffic between the cluster and the workstation — Longhorn and PBS writes to MinIO, and in-cluster apps calling the vLLM API — uses LAN addressing directly. Every host that participates in those paths is wired.

Infrastructure is addressed statically **below** the fiber box's DHCP pool, keeping `192.168.1.5`–`192.168.1.49` as the range for hosts that need a fixed address. This avoids depending on DHCP reservation support in the fiber box's firmware.

**Tailscale is retained, with its scope reduced to off-network access only:** admin surfaces and Immich from outside the house ([ADR-0007](adr-0007-cloudflare-tunnel.md)), and remote DNS filtering for cellular devices. It is no longer the transport for the backup path or the inference path, and it is no longer a dependency of disaster recovery.

### Rationale
* **The constraint that justified ADR-0010 is gone.** That ADR's central argument was that the overlay crosses NATs by design, which was the right answer to a problem the switch has since removed.
* **Tailscale comes off the recovery critical path.** ADR-0010 listed this as its main negative consequence: restoring from backup depended on an overlay that had to be healthy first. Backups now ride the LAN, so a restore needs the switch and nothing else.
* **Wire speed for the paths that move bulk data.** Backup and restore are the two operations where throughput matters most, and they no longer pay the overlay's encapsulation and userspace cost.
* **Off-network access is a genuinely separate problem.** A switch inside the house does not help a phone on cellular reach Immich, so the tier that ADR-0007 defines stands unchanged.

## Consequences

### Positive (What becomes easier?)
* **Disaster recovery has one fewer moving part.** The DR runbook no longer has to establish Tailscale connectivity and auth before a restore can begin.
* **Backups and restores run at wire speed** over gigabit ethernet instead of across an overlay on a WiFi link.
* **Troubleshooting is simpler.** A failed backup is a switch, host, or service problem, without an overlay layer to rule out first.
* **The workstation is on ethernet**, removing the WiFi link that ADR-0010 called out as a failure domain outside the homelab's control.

### Negative (What becomes harder / Risks?)
* **Service exposure is now a host responsibility.** ADR-0010 guaranteed that MinIO and vLLM bound to the Tailscale interface and were unreachable from the LAN, with Tailnet ACLs as the access control. On a flat segment that guarantee is gone, and it has already lapsed: MinIO currently listens on `0.0.0.0:9000` and `0.0.0.0:9001`, reachable by every device on the network. Access control has to move to explicit bind addresses and a host firewall on the workstation.
* **No segmentation between IoT and infrastructure.** Every wired device shares one broadcast domain. A managed switch with VLANs is the eventual answer and is deferred.

* **WiFi is still double-NATted and is not on the flat segment.** Traffic from a wireless client crosses the TP-Link's NAT before reaching the wired network, and the wired side cannot reach a wireless client at all. Anything that needs to originate from a wireless device — a phone pushing to Immich, or the workstation pushing to a service if it were ever on WiFi — has to account for that direction being one-way. Converting the TP-Link to an access point would fold WiFi onto the same segment and is the obvious follow-up, deferred here because the wired paths are what the backup and inference workloads use.
* **LAN addressing needs to be made stable.** The workstation holds a DHCP lease from the fiber box (`192.168.1.56`, inside the pool), so anything referencing it needs a static address below the pool plus a PiHole local DNS record before that reference can be trusted. Internal service names are served from PiHole under `lab.alhabli.com` and are never published to Cloudflare — the OpenTofu state backend is the first consumer, at `minio.lab.alhabli.com` ([environment README](../../tofu/environments/homelab/README.md)). Naming services rather than hosts keeps MinIO relocatable.
* **Two addressing schemes coexist.** Services are reached by LAN address at home and through the Tailnet from outside, so anything that needs to work in both places needs a name that resolves correctly in both.
* **The intermittent target model is unchanged.** The workstation is still not always on. Scheduled backups still fail and succeed on the next run ([ADR-0009](adr-0009-backup-strategy.md)), and OpenTofu still cannot run while the workstation is down.
