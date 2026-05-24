# Debian 13 Cloud-Init Template

This target creates a Proxmox VM template from the official Debian 13
`genericcloud` QCOW2 image. It does not install Debian from ISO; it imports the
prebuilt cloud image and attaches a Proxmox cloud-init drive.

## Build

Run from the repository root:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1
```

To replace an existing VM/template with the same VMID:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1 -Force
```

The script reads shared Proxmox values from `config/Proxmox.pkrvars.hcl` and
target defaults from `linux/debian-13-cloudinit/debian-13-cloudinit.pkrvars.hcl.example`.
It requires SSH access to the Proxmox node because cloud images are imported with
`qm`.

## Result

Default output:

- VMID: `9200`
- Template name: `tpl-debian-13-cloudinit`
- Boot disk: imported Debian 13 `genericcloud` QCOW2 on `scsi0`
- Cloud-init drive: `ide2`
- Console: `serial0`
- Network: DHCP on `net0`
