# Ubuntu 26.04 Cloud-Init Template Runbook

## Source Image

The template uses the official Ubuntu Server 26.04 LTS Resolute cloud image:

```text
https://cloud-images.ubuntu.com/releases/server/server/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img
```

The script downloads `SHA256SUMS` from the same directory and verifies the image
with `sha256sum` before importing it.

## Build Command

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\ubuntu-26.04-cloudinit\scripts\New-UbuntuCloudInitTemplate.ps1
```

Use `-Force` only when replacing the existing VMID/template:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\ubuntu-26.04-cloudinit\scripts\New-UbuntuCloudInitTemplate.ps1 -Force
```

## Validation

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-UbuntuCloudInitTemplate.ps1
```

Expected result:

```text
Cloud-init template is valid.
VMID: 9202
Name: tpl-ubuntu-26-04-cloudinit
Disk: local-lvm:base-9202-disk-0,discard=on,iothread=1,size=20G,ssd=1
Cloud-init: local-lvm:vm-9202-cloudinit,media=cdrom
```

## Proxmox Result

- VMID: `9202`
- Name: `tpl-ubuntu-26-04-cloudinit`
- Cloud-init user: `ubuntu`
- Network: DHCP on `net0`
- Console: `serial0` with `vga=serial0`
- QEMU agent: `enabled=1,fstrim_cloned_disks=1`
