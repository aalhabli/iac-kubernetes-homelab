# OpenTofu VM Module

A reusable OpenTofu module that clones a Cloud-Init template into a configurable virtual machine on Proxmox. This module serves as the base building block for all VMs in the homelab.

## Example Usage

```hcl
module "test_vm" {
  source = "../../modules/vm"

  name           = "test-server-01"
  node_name      = "pve"
  template_vm_id = 9000

  cpu_cores = 2
  memory_mb = 2048
  disk_size = 20

  ipv4_address = "dhcp"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | The name of the virtual machine | `string` | n/a | yes |
| `node_name` | The Proxmox node name where the VM will be placed | `string` | n/a | yes |
| `template_vm_id` | The ID of the Cloud-Init template VM to clone | `number` | n/a | yes |
| `cpu_cores` | Number of CPU cores | `number` | `2` | no |
| `memory_mb` | Amount of dedicated memory in MB | `number` | `2048` | no |
| `disk_size` | The size of the primary disk in GB | `number` | `20` | no |
| `ipv4_address` | The IPv4 address in CIDR format. Use 'dhcp' for dynamic IP. | `string` | `"dhcp"` | no |
| `ipv4_gateway` | The IPv4 gateway (required if using a static ipv4_address) | `string` | `null` | no |
| `ssh_public_keys` | List of SSH public keys to inject into the VM via Cloud-Init | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | The Proxmox VM ID of the provisioned virtual machine |
| `ipv4_addresses` | The list of IPv4 addresses assigned to the VM |
