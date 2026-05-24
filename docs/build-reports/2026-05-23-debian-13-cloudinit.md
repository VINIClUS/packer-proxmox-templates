# Debian 13 Cloud-Init Template Build Report

Date: 2026-05-23

## Result

Created the Debian 13 `trixie` cloud-init template on Proxmox.

- VMID: `9200`
- Name: `tpl-debian-13-cloudinit`
- Source image: `https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2`
- Image verification: `debian-13-genericcloud-amd64.qcow2: OK`
- Disk: `local-lvm:base-9200-disk-0,discard=on,iothread=1,size=16G,ssd=1`
- Cloud-init drive: `local-lvm:vm-9200-cloudinit,media=cdrom`
- Cloud-init user: `debian`
- Network: DHCP on `net0`
- Console: `serial0` with `vga=serial0`
- QEMU agent: `enabled=1,fstrim_cloned_disks=1`

## Commands

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-DebianCloudInitTemplateScript.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-DebianCloudInitTemplate.ps1
```

## Validation Evidence

```text
Debian cloud-init template is valid.
VMID: 9200
Name: tpl-debian-13-cloudinit
Disk: local-lvm:base-9200-disk-0,discard=on,iothread=1,size=16G,ssd=1
Cloud-init: local-lvm:vm-9200-cloudinit,media=cdrom
```

## Follow-Up

The first successful creation exposed a local script issue: PowerShell CRLF line
endings were passed through SSH and caused the final `qm config` call to receive
`9200\r`. The script now normalizes the remote payload to LF before execution.
