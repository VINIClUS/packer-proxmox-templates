# Read-Only Setup Inventory

Date: 2026-05-25
Mode: read-only discovery only
Workspace: `C:\Users\Vinicius\Projetos\packer-proxmox-templates`
Target: Proxmox `192.168.1.149`

## Scope Guardrails

- No services were restarted.
- No firewall, network, nginx, CT, or VM configuration was changed.
- Only local documentation files were generated.
- Requested spec file check: `Setup.md` exists but is empty (`0` bytes). No file named `SPEC Setup.md` exists in the repository.

## Read-Only Commands Executed

```powershell
rtk git commit --allow-empty -m "Checkpoint before read-only setup assessment"
rtk powershell -NoProfile -Command "Get-Content -LiteralPath Setup.md -Raw"
rtk rg --files | rg -i "(spec|setup).*\.md$|.*setup.*|.*spec.*"
rtk ssh root@192.168.1.149 "pveversion && qm list && pct list && pvesm status"
rtk ssh root@192.168.1.149 "qm config <vmid>"
rtk ssh root@192.168.1.149 "pct config <ctid>"
```

## Proxmox Node

- Version: `pve-manager/9.1.1/42db4a6cf33dac83`
- Kernel: `6.17.2-1-pve`
- Uptime at collection: `up 3 days, 1:28`
- Main bridge observed: `vmbr0`
- Host IP observed: `192.168.1.149/24`

## Storage

| Storage | Type | Status | Used |
|---|---:|---:|---:|
| `local` | `dir` | `active` | `18.05%` |
| `local-lvm` | `lvmthin` | `active` | `27.62%` |
| `rpool` | `zfspool` | `active` | `0.40%` |

Cloud image cache under `/var/lib/vz/template/qcow2`:

- `debian-13-genericcloud-amd64.qcow2`
- `AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2`
- `ubuntu-26.04-server-cloudimg-amd64.img`
- `SHA512SUMS`, `SHA256SUMS`, `CHECKSUM`

## VMs and Templates

| VMID | Name | Status | Template | Notes |
|---:|---|---|---|---|
| `101` | `ESUS-TESTE` | stopped | no | Debian DVD attached, `382G` disk |
| `9101` | `tpl-win11-24h2` | stopped | yes | Win11 template, `serial0=socket`, QEMU agent enabled |
| `9200` | `tpl-debian-13-cloudinit` | stopped | yes | Debian cloud-init, user `debian`, `16G` disk |
| `9201` | `tpl-almalinux-10-cloudinit` | stopped | yes | AlmaLinux cloud-init, user `almalinux`, `16G` disk |
| `9202` | `tpl-ubuntu-26-04-cloudinit` | stopped | yes | Ubuntu cloud-init, user `ubuntu`, `20G` disk |

Common Linux template controls verified on `9200`, `9201`, and `9202`:

- `template: 1`
- `boot: order=scsi0`
- `ide2: ... cloudinit`
- `ipconfig0: ip=dhcp`
- `serial0: socket`
- `vga: serial0`
- `agent: enabled=1,fstrim_cloned_disks=1`
- `scsihw: virtio-scsi-single`

## Containers

| CTID | Hostname | Status | On Boot | Notes |
|---:|---|---|---|---|
| `100` | `Netbird` | running | yes | Debian, unprivileged, `nesting=1`, TUN mounts |
| `110` | `nginx` | running | yes | Debian, unprivileged, bridge `vmbr0`, firewall enabled |
| `120` | `infisical` | running | yes | Debian, protected, tags `auth;community-script`, storage on `rpool` |

## Evidence Gaps

- `Setup.md` is empty, so phases 0-3 could not be mapped to the requested spec.
- No nginx runtime/service inspection was performed inside CT `110`; the constraint explicitly prohibited service changes, and no spec content defined required nginx read checks.
