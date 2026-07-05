# Proxmox Golden Image (Ubuntu 26.04)

## Context
In a modern cloud-native environment, infrastructure must be treated as immutable ("cattle, not pets"). We do not manually install operating systems from ISO files. Instead, we rely on OpenTofu (IaC) to rapidly clone pre-configured VM templates.

This document outlines the exact steps taken to build the Golden Image on the Proxmox bare-metal host. 

This Golden Image serves as the foundation for the entire Kubernetes (k3s) cluster and any standalone VMs. It utilizes **Cloud-Init** (the exact same technology used by AWS EC2) to dynamically inject IP addresses, hostnames, and SSH keys upon first boot.

### Required Injections
To ensure OpenTofu can communicate with the cloned VMs, the `qemu-guest-agent` must be baked into the image. This agent reports the dynamically assigned IP address back to the Proxmox hypervisor so that OpenTofu knows the VM has successfully booted and can hand off the process to Ansible.

---

## Build Steps

The following steps are executed directly on the Proxmox host via SSH as `root`.

### 1. Download the Cloud Image
We use the official Ubuntu 26.04 LTS (Resolute Raccoon) Cloud Image.
```bash
wget https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img
```

### 2. Inject the Guest Agent Offline
Instead of booting the image to install software, we use `virt-customize` (part of `libguestfs-tools`) to mount the disk offline and inject the agent natively.

```bash
# Install tools if missing
apt update && apt install -y libguestfs-tools

# Inject the agent
virt-customize -a resolute-server-cloudimg-amd64.img --install qemu-guest-agent
```
*   **`-a`**: Adds the specified disk image.
*   **`--install`**: Runs the native package manager (`apt`) inside the offline image to install the package.

### 3. Create the VM Skeleton
We create an empty Virtual Machine assigned to a high ID (`9000`) so it stays grouped as a template.

```bash
qm create 9000 --name "ubuntu-2604-cloudinit-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
```
*   **`--net0 virtio,bridge=vmbr0`**: Connects the VM to the physical network via the default `vmbr0` bridge, using the highly optimized `virtio` paravirtualized network driver.

### 4. Import the Disk to Storage
We move the raw `.img` file into Proxmox's managed storage (`local-lvm`).
```bash
qm importdisk 9000 resolute-server-cloudimg-amd64.img local-lvm
```

### 5. Configure Hardware and Cloud-Init
We map the imported disk to an optimized SCSI controller, add the required Cloud-Init CD-ROM drive, and set the boot order.

```bash
# Attach the disk to a high-performance SCSI controller
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# Add a virtual CD-ROM drive for Cloud-Init configuration
qm set 9000 --ide2 local-lvm:cloudinit

# Set boot order to the SCSI drive
qm set 9000 --boot c --bootdisk scsi0

# Route display output to a serial console (standard for cloud images)
qm set 9000 --serial0 socket --vga serial0

# Enable the hypervisor to listen for the qemu-guest-agent
qm set 9000 --agent enabled=1
```

### 6. Convert to Template
With the hardware configured, we lock the VM to prevent accidental changes, turning it into a read-only template that OpenTofu can safely clone.

```bash
# Clean up the raw download
rm resolute-server-cloudimg-amd64.img

# Convert to template
qm template 9000
