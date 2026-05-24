# Ubuntu 26.04 Cloud-Init Template

This target creates a Proxmox VM template from the official Ubuntu Server
26.04 LTS `Resolute Raccoon` cloud image for amd64.

## Build

Run from the repository root:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\ubuntu-26.04-cloudinit\scripts\New-UbuntuCloudInitTemplate.ps1
```

To replace an existing VM/template with the same VMID:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\ubuntu-26.04-cloudinit\scripts\New-UbuntuCloudInitTemplate.ps1 -Force
```

The script reads shared Proxmox values from `config/Proxmox.pkrvars.hcl` and
target defaults from `linux/ubuntu-26.04-cloudinit/ubuntu-26.04-cloudinit.pkrvars.hcl.example`.

## Result

Default output:

- VMID: `9202`
- Template name: `tpl-ubuntu-26-04-cloudinit`
- Boot disk: imported Ubuntu 26.04 cloud image on `scsi0`
- Cloud-init drive: `ide2`
- Console: `serial0`
- Network: DHCP on `net0`
