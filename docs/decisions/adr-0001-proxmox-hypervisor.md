# Use Proxmox VE on a Laptop as the Bare-Metal Hypervisor

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
We need a foundational virtualization layer to host a multi-node Kubernetes (k3s) cluster alongside other standalone infrastructure services (like DNS and backups). The target hardware is a single ThinkPad L14 Gen 4 (Intel 13th-Gen, 64GB RAM, 2TB NVMe). We need to determine the best operating system/platform to manage these virtual machines and Linux containers (LXCs) efficiently while maximizing the unique hardware traits of a laptop.

## Alternatives Considered
* **Bare-metal Linux (Ubuntu/Debian) with KVM/libvirt:** Managing VMs directly via CLI or tools like Cockpit.
* **VMware ESXi:** Industry-standard enterprise hypervisor.
* **Running everything directly on the host OS:** No virtualization layer; installing Kubernetes directly on the base OS.
* **Omarchy Linux:** A rolling-release Linux distribution.
* **Fedora Silverblue DX:** An immutable, container-first OS optimized for developer experiences.

## Decision
We will install **Proxmox Virtual Environment (VE)** directly on the ThinkPad laptop as the bare-metal hypervisor.

### Rationale
* **Battery as a built-in UPS:** This is the primary driver for using a laptop. By running Proxmox, we can configure the host OS to detect power loss (unplugged AC) and trigger a graceful shutdown of all VMs, containers, and the host itself before the battery dies. This mimics an enterprise Uninterruptible Power Supply (UPS) without the extra cost or physical footprint.
* **LXC Support:** Proxmox has first-class support for Linux Containers (LXC). This allows us to run services that don't belong in Kubernetes (like PiHole for DNS) with near-zero overhead compared to full VMs.
* **Web UI and API:** Proxmox provides a robust web interface for manual management and, crucially, a rich API that our Infrastructure as Code (OpenTofu) can target for automated provisioning.
* **Rejection of ESXi:** Broadcom's recent acquisition of VMware and subsequent licensing changes make ESXi an unstable choice for open-source and homelab environments. Proxmox is the clear industry alternative gaining traction.
* **Rejection of bare-metal KVM:** While educational, managing KVM via CLI lacks the "platform" feel of Proxmox and makes declarative provisioning with OpenTofu significantly more complex.
* **Rejection of Omarchy Linux & Fedora Silverblue DX:** While both offer excellent modern desktop or container-first experiences (especially Silverblue's immutable architecture), they lack the purpose-built, bare-metal hypervisor capabilities, built-in LXC support, and API-driven provisioning ecosystem (like the OpenTofu Proxmox provider) that a dedicated hypervisor provides. They were tested but ultimately proved better suited for daily-driver developer workstations than a headless virtualization host.

## Consequences

### Positive (What becomes easier?)
* We get enterprise-grade VM and container management with a declarative API.
* We gain built-in protection against sudden power outages (data corruption) thanks to the laptop battery and Proxmox power management scripts.
* Efficient resource usage via LXCs for non-k8s workloads.

### Negative (What becomes harder/Risks?)
* **Lid/Sleep management:** We will need to actively modify the Proxmox base OS (Debian) `logind.conf` to ignore lid-close events so the server doesn't go to sleep when the laptop is closed.
* **Battery health management:** We will need to use tlp-cli to manage start-charge and end-charge variables to maintain a battery charge minimum of 40% and maximum of 60%. This range is best practice to maximize longevity of the battery chemistry while serving as a UPS in an always-on server laptop.
* **Networking complexity:** We must configure Proxmox bridges over a single physical NIC (or Wi-Fi, though Ethernet is highly preferred) to support our VLANs.
