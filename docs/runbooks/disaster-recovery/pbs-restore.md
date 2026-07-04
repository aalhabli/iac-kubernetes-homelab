# Runbook: Restoring a VM/LXC from Proxmox Backup Server

**Objective:** Safely restore a corrupted, failed, or missing VM/LXC from the `pbs-local` Proxmox Backup Server datastore.

## Prerequisites
- Access to the Proxmox VE Web UI.
- The `pbs-local` storage must be online and reachable at `192.168.1.4`.

## Procedure

### Step 1: Locate the Backup
1. Log in to the Proxmox VE Web UI.
2. In the left navigation tree, select the target node (e.g., `pve`).
3. Under the node, select the **`pbs-local`** storage.
4. Click on **Backups** in the middle pane.
5. You will see a list of all deduplicated snapshots available for your VMs and LXCs.

### Step 2: Initiate the Restore
1. Find the VM/LXC ID you need to restore (e.g., `100` for pihole).
2. Click on the specific snapshot timestamp you want to revert to.
3. Click the **Restore** button at the top of the pane.

### Step 3: Configure Restore Parameters
A dialog box will appear. Ensure the following settings are correct:
- **Storage:** Select the target storage on the PVE host where the VM disks should live (e.g., `local-lvm`).
- **VM ID:** 
  - If you are replacing a completely destroyed VM, you can keep the original ID.
  - If the original VM still exists and you want to test the restore side-by-side, assign a **new, unused VM ID** (e.g., `9100`).
- **Start after restore:** Check this box if you want the VM to boot immediately upon completion.

### Step 4: Execute and Verify
1. Click **Restore**.
2. A task log window will appear showing the extraction process. Because PBS uses chunk deduplication, this is usually very fast.
3. Once it says `TASK OK`, close the window.
4. Verify the restored VM/LXC appears in your Datacenter view and boots successfully.

---
*Note: If you restored over an existing VM ID, ensure you power down the broken VM before initiating the restore.*
