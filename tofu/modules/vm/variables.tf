variable "name" {
  description = "The name of the virtual machine"
  type        = string
}

variable "node_name" {
  description = "The Proxmox node name where the VM will be placed"
  type        = string
}

variable "template_vm_id" {
  description = "The ID of the Cloud-init tempalte VM to clone"
  type        = number
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Amount of dedicated memory in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "The size of the primary disk in GB"
  type        = number
  default     = 20
}

variable "ipv4_address" {
  description = "IPv4 address in CIDR format"
  type        = string
  default     = "dhcp"
}

variable "ipv4_gateway" {
  description = "The IPv4 gateway - required if using a static IP address"
  type        = string
  default     = null
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject into the VM via Cloud-init"
  type        = list(string)
  default     = []
}

variable "username" {
  description = "Username for the VM that instructs what user account to create and inject the SSH keys into"
  type        = string
  default     = "ubuntu"
}
