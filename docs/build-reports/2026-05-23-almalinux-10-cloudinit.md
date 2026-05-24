# AlmaLinux 10 Cloud-Init Template Build Report

Date: 2026-05-23

## Result

Created the AlmaLinux 10.1 GenericCloud cloud-init template on Proxmox.

- VMID: `9201`
- Name: `tpl-almalinux-10-cloudinit`
- Source image: `https://repo.almalinux.org/almalinux/10.1/cloud/x86_64_v2/images/AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2`
- Image verification: `AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2: OK`
- Disk: `local-lvm:base-9201-disk-0,discard=on,iothread=1,size=16G,ssd=1`
- Cloud-init drive: `local-lvm:vm-9201-cloudinit,media=cdrom`
- Cloud-init user: `almalinux`
- Network: DHCP on `net0`
- Console: `serial0` with `vga=serial0`
- QEMU agent: `enabled=1,fstrim_cloned_disks=1`

## Commands

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-CloudInitTemplateScripts.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\almalinux-10-cloudinit\scripts\New-AlmaLinuxCloudInitTemplate.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-AlmaLinuxCloudInitTemplate.ps1
```

## Validation Evidence

```text
Cloud-init template is valid.
VMID: 9201
Name: tpl-almalinux-10-cloudinit
Disk: local-lvm:base-9201-disk-0,discard=on,iothread=1,size=16G,ssd=1
Cloud-init: local-lvm:vm-9201-cloudinit,media=cdrom
```

## Follow-Up

The template was created successfully. The post-create script path was hardened
to remove carriage returns on the remote side before executing bash, preventing
PowerShell line endings from affecting final `qm config` calls.
