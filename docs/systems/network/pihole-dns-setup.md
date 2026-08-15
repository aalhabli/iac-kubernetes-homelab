# Architecture & Deployment: Network-Wide Ad-Blocking (PiHole + Tailscale)

## 1. Overview
This document outlines the architecture, design decisions, and implementation details for the network-wide DNS filtering system. The core objective is to provide zero-maintenance ad and malware blocking for all local network devices and remote cellular devices.

## 2. Architecture & Topology

### Physical Topology
During initial deployment, a critical hardware limitation was identified: the ISP-provided Fiber Box enforced unconfigurable "Client Isolation" between its physical LAN ports, severing Layer 2 communication between the primary WiFi Router and the Proxmox virtualization host.

**Architectural Decision:**
Rather than compromising the TP-Link AXE5400's routing capabilities by forcing it into Bridge/AP Mode, I moved the whole local network off the fiber box's internal switch and onto a dedicated switch.
* The TP-Link, the Proxmox host, and the RTX 4090 workstation all connect to the same unmanaged gigabit switch.
* That switch is uplinked to the ISP Fiber Box, which now sees a single downstream port.
* **Result:** All local MAC-to-MAC traffic stays on the switch at wire speed, bypassing the fiber box's client isolation entirely. Every host sits on one L2 segment in `192.168.1.0/24`.

This is what retired Tailscale as the transport between the cluster and the workstation ([ADR-0011](../../decisions/adr-0011-flat-l2-network.md)). The workstation was previously on WiFi behind the TP-Link's NAT, on a separate segment from the server.

Verified from the workstation on 2026-08-15 with Tailscale stopped: the Proxmox host (`192.168.1.200`), PBS (`192.168.1.4`), and this PiHole (`192.168.1.3`) each answer in under 1 ms, one hop away, with directly resolved MAC addresses.

### Virtualization & Networking
- **Platform:** Proxmox LXC (Container 100)
- **OS:** Debian 12
- **Network Interface:** `veth` bridged to `vmbr0`
- **Static IP Assignment:** `192.168.1.3/24` (Gateway: `192.168.1.1`)

## 3. Implementation Details

### LXC Configuration (VPN Tunnel Support)
To support Tailscale's WireGuard backend within an unprivileged LXC sandbox, the container required explicit access to the host's tunnel device.
Modified `/etc/pve/lxc/100.conf` on the Proxmox host to allow `/dev/net/tun` passthrough:
```text
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

### Edge DHCP Configuration (Fiber Box)
To enforce DNS filtering across the entire physical property (Smart TVs, IoT devices, local laptops), the DHCP server handing out addresses must advertise the PiHole as the resolver.

**The DHCP server for the wired segment is the ISP fiber box at `192.168.1.1`, not the TP-Link.** The fiber box owns `192.168.1.0/24`, serves the pool `192.168.1.50`–`192.168.1.199`, and advertises itself as both gateway and DNS. The TP-Link takes a lease from that pool on its WAN port and NATs its own separate `192.168.0.0/24` WiFi network behind it, so its DHCP settings only affect wireless clients.

Settings to apply, under Network » LAN Settings » DHCP Service on the fiber box:
* **DHCP Primary DNS:** `192.168.1.3` (currently `192.168.1.1`).
* **Failover Prevention:** leave DHCP Secondary DNS empty. Specifying a fallback (e.g. 8.8.8.8) allows hard-coded client devices to bypass the PiHole entirely.
* The TP-Link needs the same treatment separately for wireless clients, since they never see the fiber box's DHCP.

> **Known issue as of 2026-08-15 — network-wide DNS filtering is still bypassed.** The fiber box advertises `domain_name_servers = 192.168.1.1`, so every device that takes a lease resolves through the fiber box instead of the PiHole. The workstation is the exception, and only because its resolver is pinned locally in NetworkManager (`ipv4.dns=192.168.1.3`, `ipv4.ignore-auto-dns=yes`) rather than fixed at the DHCP layer. The PiHole itself is healthy and answering on port 53. Verify with `resolvectl status` on a client that has *not* been pinned.

### Remote Ad-Blocking (Tailscale)
To extend the DNS filtering perimeter to cellular networks (5G/LTE):
1. The PiHole's Tailscale interface (`100.113.126.122`) was designated as a Custom Global Nameserver in the Tailscale Admin Console.
2. **"Override local DNS"** was enabled, forcing all authenticated Tailnet devices to tunnel DNS queries back to the home infrastructure, regardless of their physical location.

## 4. Threat Intelligence & Blocklists
Optimizing for "Quality over Quantity" (The Family Test) to prevent breaking legitimate services while maximizing security. A gravity database of ~1.85 million domains was compiled using the following 2026 industry standards:
* **Core Protection:** HaGeZi Multi Normal (`multi.txt`) - Balances aggressive blocking with zero expected breakage.
* **Zero False Positive:** OISD Big (`big.oisd.nl`) - The largest heavily curated baseline.
* **Malware/Phishing:** HaGeZi Threat Intelligence Feeds (`tif.txt`) - Dedicated security feed targeting active malicious infrastructure.
