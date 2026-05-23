packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  answer_files = {
    "Autounattend.xml" = templatefile(abspath("${path.root}/http/Autounattend.xml.pkrtpl"), {
      winrm_username          = var.winrm_username
      winrm_password          = var.winrm_password
      local_admin_full_name   = var.local_admin_full_name
      local_admin_description = var.local_admin_description
      windows_edition         = var.windows_edition
      windows_product_key     = var.windows_product_key
      timezone                = var.timezone
      system_locale           = var.system_locale
      input_locale            = var.input_locale
      user_locale             = var.user_locale
      computer_name           = var.computer_name
    })
  }
}

source "proxmox-iso" "windows_11" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.proxmox_insecure_skip_tls
  node                     = var.proxmox_node

  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_name        = var.template_name
  template_description = "${var.template_description} Built ${timestamp()}."
  tags                 = "windows;win11;packer;template"

  os              = "win11"
  qemu_agent      = true
  boot            = "order=sata0;ide0;scsi0"
  bios            = "ovmf"
  machine         = "q35"
  cpu_type        = "host"
  cores           = var.cpu_cores
  sockets         = var.cpu_sockets
  memory          = var.memory_mb
  scsi_controller = "virtio-scsi-single"
  serials         = ["socket"]

  efi_config {
    efi_storage_pool  = var.proxmox_vm_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  tpm_config {
    tpm_storage_pool = var.proxmox_vm_storage_pool
    tpm_version      = "v2.0"
  }

  disks {
    type         = "scsi"
    storage_pool = var.proxmox_vm_storage_pool
    disk_size    = var.disk_size
    format       = "raw"
    io_thread    = true
    discard      = true
    ssd          = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.proxmox_network_bridge
    firewall = true
  }

  boot_iso {
    type         = "sata"
    iso_file     = var.windows_iso_file
    iso_checksum = var.windows_iso_checksum
    unmount      = true
  }

  additional_iso_files {
    type     = "sata"
    iso_file = var.virtio_iso_file
    unmount  = true
  }

  additional_iso_files {
    type             = "ide"
    iso_storage_pool = var.proxmox_iso_storage_pool
    cd_content       = local.answer_files
    cd_files = [
      abspath("${path.root}/http/scripts/Configure-WinRM.ps1"),
      abspath("${path.root}/http/scripts/Install-QemuGuestAgent.ps1")
    ]
    unmount = true
  }

  http_directory = abspath("${path.root}/http")
  boot_wait      = "5s"
  boot_command = [
    "<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar>"
  ]

  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_timeout  = "2h"
  winrm_use_ssl  = false
  winrm_insecure = true

  pause_before_connecting = "2m"
}

build {
  name    = "win11-24h2-proxmox"
  sources = ["source.proxmox-iso.windows_11"]

  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password

    scripts = [
      abspath("${path.root}/scripts/Install-VirtIO.ps1"),
      abspath("${path.root}/scripts/Configure-EnterpriseRemoting.ps1"),
      abspath("${path.root}/scripts/Optimize-Template.ps1")
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password

    scripts = [
      abspath("${path.root}/scripts/Sysprep-Template.ps1")
    ]
  }
}
