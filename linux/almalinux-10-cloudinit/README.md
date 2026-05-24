# AlmaLinux 10 Cloud-Init Template

This target creates a Proxmox VM template from the official AlmaLinux 10.1
`GenericCloud` QCOW2 image for `x86_64_v2`.

## Build

Run from the repository root:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\almalinux-10-cloudinit\scripts\New-AlmaLinuxCloudInitTemplate.ps1
```

To replace an existing VM/template with the same VMID:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\almalinux-10-cloudinit\scripts\New-AlmaLinuxCloudInitTemplate.ps1 -Force
```

The script reads shared Proxmox values from `config/Proxmox.pkrvars.hcl` and
target defaults from `linux/almalinux-10-cloudinit/almalinux-10-cloudinit.pkrvars.hcl.example`.

## Result

Default output:

- VMID: `9201`
- Template name: `tpl-almalinux-10-cloudinit`
- Boot disk: imported AlmaLinux 10.1 GenericCloud QCOW2 on `scsi0`
- Cloud-init drive: `ide2`
- Console: `serial0`
- Network: DHCP on `net0`
