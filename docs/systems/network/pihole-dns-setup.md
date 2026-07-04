# Architecture & Deployment: Network-Wide Ad-Blocking (PiHole + Tailscale)

## 1. Overview
This document outlines the architecture, design decisions, and implementation details for the network-wide DNS filtering system. The core objective is to provide zero-maintenance ad and malware blocking for all local network devices and remote cellular devices.

## 2. Architecture & Topology

### Physical Topology Bypass
During initial deployment, a critical hardware limitation was identified: the ISP-provided Fiber Box enforced unconfigurable "Client Isolation" between its physical LAN ports, severing Layer 2 communication between the primary WiFi Router and the Proxmox virtualization host.

**Architectural Decision:** 
Rather than compromising the TP-Link AXE5400's routing capabilities by forcing it into Bridge/AP Mode, I engineered a physical Layer 2 bypass. 
* Both the TP-Link WAN port and the Proxmox Server eth0 interface are connected directly to an unmanaged gigabit switch.
* The unmanaged switch is then uplinked to the ISP Fiber Box.
* **Result:** The unmanaged switch handles all local MAC-to-MAC routing between the subnets at wire speed, completely bypassing the ISP router's internal switch chip and restoring full local connectivity.

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

### Edge Router Configuration (TP-Link)
To enforce DNS filtering across the entire physical property (Smart TVs, IoT devices, local laptops):
* **DHCP Server Settings:** The TP-Link DHCP Server was configured to distribute `192.168.1.3` as the Primary DNS.
* **Failover Prevention:** The Secondary DNS field is intentionally omitted. Specifying a fallback (e.g., 8.8.8.8) allows hard-coded client devices to bypass the PiHole entirely.

### Remote Ad-Blocking (Tailscale)
To extend the DNS filtering perimeter to cellular networks (5G/LTE):
1. The PiHole's Tailscale interface (`100.113.126.122`) was designated as a Custom Global Nameserver in the Tailscale Admin Console.
2. **"Override local DNS"** was enabled, forcing all authenticated Tailnet devices to tunnel DNS queries back to the home infrastructure, regardless of their physical location.

## 4. Threat Intelligence & Blocklists
Optimizing for "Quality over Quantity" (The Family Test) to prevent breaking legitimate services while maximizing security. A gravity database of ~1.85 million domains was compiled using the following 2026 industry standards:
* **Core Protection:** HaGeZi Multi Normal (`multi.txt`) - Balances aggressive blocking with zero expected breakage.
* **Zero False Positive:** OISD Big (`big.oisd.nl`) - The largest heavily curated baseline.
* **Malware/Phishing:** HaGeZi Threat Intelligence Feeds (`tif.txt`) - Dedicated security feed targeting active malicious infrastructure.
