# Debian 13 Cloud-Init Template Runbook

## Source Image

The template uses the official Debian cloud image:

```text
https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
```

Debian 13 `trixie` is the current stable Debian release, and the Debian Cloud
team publishes `genericcloud` images for virtualized environments. The script
downloads `SHA512SUMS` from the same `latest` directory and verifies the image
when `sha512sum` is available on the Proxmox node.

## Build Command

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1
```

Use `-Force` only when replacing the existing VMID/template:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1 -Force
```

## Proxmox Result

Default template settings:

- VMID: `9200`
- Name: `tpl-debian-13-cloudinit`
- Disk storage: `proxmox_vm_storage_pool`, default `local-lvm`
- Cloud-init storage: `cloud_init_storage_pool`, default `local-lvm`
- Network: `virtio` on `proxmox_network_bridge`, default `vmbr0`
- Console: `serial0` with `vga=serial0`
- Cloud-init defaults: DHCP on `net0`, user `debian`

## Validation

After creation, run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-DebianCloudInitTemplate.ps1
```

Expected result for the default target:

```text
Debian cloud-init template is valid.
VMID: 9200
Name: tpl-debian-13-cloudinit
Disk: local-lvm:base-9200-disk-0,discard=on,iothread=1,size=16G,ssd=1
Cloud-init: local-lvm:vm-9200-cloudinit,media=cdrom
```

## Notes

The script requires SSH to the Proxmox node because Proxmox cloud images are
imported through `qm` using `import-from`. The API token remains necessary for
Packer ISO builds, while this Debian cloud-image path uses SSH for Proxmox CLI
operations.

The PowerShell script normalizes the remote shell payload to LF before piping it
to SSH. This avoids CRLF being interpreted as part of shell variable values by
`bash` on the Proxmox node.
