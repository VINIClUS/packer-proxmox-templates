# AlmaLinux 10 Cloud-Init Template Runbook

## Source Image

The template uses the official AlmaLinux GenericCloud image:

```text
https://repo.almalinux.org/almalinux/10.1/cloud/x86_64_v2/images/AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2
```

The script downloads `CHECKSUM` from the same directory and verifies the image
with `sha256sum` before importing it.

## Build Command

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\almalinux-10-cloudinit\scripts\New-AlmaLinuxCloudInitTemplate.ps1
```

Use `-Force` only when replacing the existing VMID/template:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\almalinux-10-cloudinit\scripts\New-AlmaLinuxCloudInitTemplate.ps1 -Force
```

## Validation

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-AlmaLinuxCloudInitTemplate.ps1
```

Expected result:

```text
Cloud-init template is valid.
VMID: 9201
Name: tpl-almalinux-10-cloudinit
Disk: local-lvm:base-9201-disk-0,discard=on,iothread=1,size=16G,ssd=1
Cloud-init: local-lvm:vm-9201-cloudinit,media=cdrom
```

## Proxmox Result

- VMID: `9201`
- Name: `tpl-almalinux-10-cloudinit`
- Cloud-init user: `almalinux`
- Network: DHCP on `net0`
- Console: `serial0` with `vga=serial0`
- QEMU agent: `enabled=1,fstrim_cloned_disks=1`
