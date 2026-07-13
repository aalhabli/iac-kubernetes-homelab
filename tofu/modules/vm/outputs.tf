output "vm_id" {
  description = "The Proxmox VM ID of the provisioned virtual machine"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_addresses" {
  description = "The list of IPv4 addresses assigned to the VM"
  # The bpg/proxmox provider returns this as a list.
  # Often, index 0 is the loopback (127.0.0.1) and index 1 is the actual network IP.
  value = proxmox_virtual_environment_vm.this.ipv4_addresses
}
