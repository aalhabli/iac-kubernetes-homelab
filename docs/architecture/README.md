# Platform Architecture

![Network Topology](network-topology.png)

This directory contains the high-level architectural diagrams and detailed deployment records for the homelab infrastructure. 

## Architecture Documents
* **[Network-Wide Ad-Blocking (PiHole + Tailscale)](pihole-dns-setup.md)**: Details the network's DNS strategy, the ISP physical bypass, and the 5G Tailscale integration.

---

## 1. The Addressing Contract (The Flat Network)
Due to the physical limitations of the ISP Fiber Box (Client Isolation bugs) and the Unmanaged Gigabit Switch (which strips 802.1q VLAN tags), the homelab intentionally utilizes a flat network topology rather than isolated VLANs. 

This ensures that the consumer edge router (TP-Link AXE5400) can natively route traffic to the Proxmox virtualization server without requiring complex internal Proxmox NAT rules or a dedicated virtual firewall (like OPNsense).

* **`192.168.0.x` (WiFi Network):** Client devices (Phones, Laptops, Smart TVs) managed by the TP-Link AXE5400.
* **`192.168.1.x` (Infrastructure Network):** The core physical and virtual infrastructure. Includes the Proxmox Host, PiHole LXC, Proxmox Backup LXC, and all Kubernetes (K3s) virtual machines.

## 2. The Tailscale Overlay Network
While the physical switch bypass solved the immediate LAN routing issues, the network inherently features a Double-NAT topology (the `192.168.0.x` WiFi network sitting behind the `192.168.1.x` ISP network). 

To ensure highly secure, zero-config remote access without opening any inbound ports on the ISP router, **Tailscale** is deployed as a WireGuard overlay. 
* **Remote DNS:** Mobile devices on cellular networks tunnel their DNS queries to the PiHole's Tailscale IP (`100.113.126.122`) for global ad-blocking.
* **Admin Access:** All SSH and Proxmox Web UI traffic flows over the `100.x.x.x` overlay, guaranteeing management access from anywhere in the world.

## 3. Kubernetes Ingress (Upcoming)
The Kubernetes cluster (K3s) will utilize MetalLB to allocate IP addresses from a reserved block on the flat `192.168.1.x` subnet (e.g., `192.168.1.100-150`). A Traefik Ingress controller will serve as the gateway, securely terminating SSL traffic routed from the public internet via Cloudflare Tunnels (outbound-only).
