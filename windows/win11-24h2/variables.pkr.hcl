variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL, including /api2/json."
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node that will run the temporary VM."
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID in user@realm!tokenid format."
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API token secret."
  sensitive   = true
}

variable "proxmox_insecure_skip_tls" {
  type        = bool
  description = "Skip Proxmox TLS verification for self-signed certificates."
  default     = true
}

variable "proxmox_iso_storage_pool" {
  type        = string
  description = "Storage pool used for generated answer ISO uploads."
  default     = "local"
}

variable "proxmox_vm_storage_pool" {
  type        = string
  description = "Storage pool used for VM disks and EFI vars."
  default     = "local-lvm"
}

variable "proxmox_network_bridge" {
  type        = string
  description = "Proxmox bridge connected to the template VM."
  default     = "vmbr0"
}

variable "proxmox_ssh_host" {
  type        = string
  description = "Shared Proxmox SSH host value accepted by this target to keep global var files reusable."
  default     = null
}

variable "proxmox_ssh_port" {
  type        = number
  description = "Shared Proxmox SSH port value accepted by this target to keep global var files reusable."
  default     = null
}

variable "proxmox_ssh_user" {
  type        = string
  description = "Shared Proxmox SSH user value accepted by this target to keep global var files reusable."
  default     = null
}

variable "proxmox_ssh_private_key_file" {
  type        = string
  description = "Shared Proxmox SSH key path accepted by this target to keep global var files reusable."
  default     = null
  sensitive   = true
}

variable "proxmox_vlan_tag" {
  type        = number
  description = "Reserved for future tagged network support. Untagged Proxmox NICs must omit vlan_tag instead of using 0."
  default     = 0
}

variable "windows_iso_file" {
  type        = string
  description = "Proxmox datastore path to the Windows ISO."
}

variable "windows_iso_checksum" {
  type        = string
  description = "Checksum for the Windows ISO, or none for a local trusted ISO."
  default     = "none"
}

variable "virtio_iso_file" {
  type        = string
  description = "Proxmox datastore path to the VirtIO driver ISO."
}

variable "winrm_username" {
  type        = string
  description = "Temporary local administrator used by Packer over WinRM."
  default     = "Administrator"
}

variable "winrm_password" {
  type        = string
  description = "Temporary WinRM password injected into Autounattend.xml."
  sensitive   = true
}

variable "local_admin_full_name" {
  type        = string
  description = "Full name for the temporary local administrator."
  default     = "Packer Local Administrator"
}

variable "local_admin_description" {
  type        = string
  description = "Description for the temporary local administrator."
  default     = "Temporary Administrator account used only during Packer image creation."
}

variable "vm_id" {
  type        = number
  description = "Temporary Proxmox VM ID."
  default     = 9101
}

variable "vm_name" {
  type        = string
  description = "Temporary VM name during the build."
  default     = "win11-24h2-packer"
}

variable "template_name" {
  type        = string
  description = "Final Proxmox template name."
  default     = "tpl-win11-24h2"
}

variable "template_description" {
  type        = string
  description = "Final Proxmox template description."
  default     = "Windows 11 24H2 golden image built by Packer for Proxmox."
}

variable "cpu_cores" {
  type        = number
  description = "CPU cores assigned to the temporary VM."
  default     = 4
}

variable "cpu_sockets" {
  type        = number
  description = "CPU sockets assigned to the temporary VM."
  default     = 1
}

variable "memory_mb" {
  type        = number
  description = "Memory assigned to the temporary VM."
  default     = 8192
}

variable "disk_size" {
  type        = string
  description = "Windows system disk size."
  default     = "80G"
}

variable "windows_edition" {
  type        = string
  description = "Windows edition name passed to setup."
  default     = "Windows 11 Enterprise"
}

variable "windows_product_key" {
  type        = string
  description = "Generic setup key used only to bypass the Windows setup product-key prompt."
  default     = "NPPR9-FWDCX-D2C8J-H872K-2YT43"
  sensitive   = true
}

variable "timezone" {
  type        = string
  description = "Windows time zone ID."
  default     = "E. South America Standard Time"
}

variable "system_locale" {
  type        = string
  description = "Windows system locale."
  default     = "en-US"
}

variable "input_locale" {
  type        = string
  description = "Windows keyboard/input locale."
  default     = "en-US"
}

variable "user_locale" {
  type        = string
  description = "Windows user locale."
  default     = "en-US"
}

variable "computer_name" {
  type        = string
  description = "Temporary computer name used during image creation."
  default     = "WIN11-PACKER"
}
