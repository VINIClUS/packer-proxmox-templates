# Windows 11 24H2 Cloudbase-Init Build Report

## Summary

Updated Proxmox template `9101` / `tpl-win11-24h2` so Windows clones can consume
Proxmox Cloud-Init ConfigDrive data through Cloudbase-Init.

## Template Build

- Proxmox node: `pve-01`
- Template VMID: `9101`
- Template name: `tpl-win11-24h2`
- Build timestamp in Proxmox description: `2026-06-10T02:02:30Z`
- Packer result: template created successfully
- Build duration: 40 minutes 35 seconds
- Generated Packer answer ISO: removed by Packer after conversion

Command:

```powershell
rtk packer build -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
```

## Validation

Validation clone `7001` was created from template `9101`, configured with:

- `citype=configdrive2`
- `ciuser=cpd`
- `ide2=rpool:vm-7001-cloudinit,media=cdrom`
- SSH public key from the local operator keypair
- DHCP networking

Observed result:

- First boot exposed guest IPv4 `192.168.1.99` through QEMU Guest Agent.
- After Cloudbase-Init completed its boot cycle, SSH public-key authentication as
  `cpd` succeeded and returned `win11-cloudbase\cpd`.
- Inside the guest, `QEMU-GA` reported `Running`.
- The validation clone `7001` and temporary Proxmox public-key file were removed
  after the test.

## Notes

Cloudbase-Init created its default `Admin` account from the ConfigDrive metadata,
but Proxmox also emits `ciuser` in Linux-style `user_data`. The template now
installs a Cloudbase LocalScript that reads `openstack\latest\user_data`, creates
the requested Proxmox `ciuser`, adds it to `Administrators`, and writes SSH
authorized keys without logging the key material.
