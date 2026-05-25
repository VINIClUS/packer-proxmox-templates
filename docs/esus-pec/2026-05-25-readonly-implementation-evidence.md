# e-SUS PEC Read-Only Implementation Evidence

Date: 2026-05-25
Scope: phases 0-3 of `docs/setup-readonly/2026-05-25-implementation-plan.md`
Mode: read-only implementation, testing, validation, and documentation.

## Commands Executed

All commands were read-only. No VM/CT was started, stopped, rebooted, modified,
or snapshotted.

```powershell
rtk ssh root@192.168.1.149 "pveversion && qm list && pct list && pvesm status"
rtk ssh root@192.168.1.149 "qm config 101; qm config 9101; qm config 9200; qm config 9201; qm config 9202"
rtk ssh root@192.168.1.149 "pct config 100; pct config 110; pct config 120"
rtk ssh root@192.168.1.149 "find /var/lib/vz /root /mnt /srv -maxdepth 6 -type f \( -iname 'eSUS-AB-PEC-*.jar' -o -iname '*PEC*.jar' \)"
rtk ssh root@192.168.1.149 "pct exec 110 -- nginx -t"
rtk powershell -NoProfile -ExecutionPolicy Bypass -File shared/scripts/Get-EsusPecInstaller.ps1 -Platform Linux -DryRun
```

## Proxmox Inventory

- Proxmox: `pve-manager/9.1.1/42db4a6cf33dac83`, kernel `6.17.2-1-pve`.
- VM `101`: `ESUS-TESTE`, stopped, Debian/Linux type, `382G` disk.
- VM template `9101`: `tpl-win11-24h2`, stopped, template.
- VM template `9200`: `tpl-debian-13-cloudinit`, stopped, template.
- VM template `9201`: `tpl-almalinux-10-cloudinit`, stopped, template.
- VM template `9202`: `tpl-ubuntu-26-04-cloudinit`, stopped, template.
- CT `100`: `Netbird`, running.
- CT `110`: `nginx`, running.
- CT `120`: `infisical`, running, protected.

## Storage Inventory

- `local`: active, about `18.05%` used.
- `local-lvm`: active, about `27.62%` used.
- `rpool`: active, about `0.40%` used.

## Target Assessment

Current evidence indicates CT `120` is not the e-SUS PEC application; it is
`infisical` and has `protection: 1`. The likely e-SUS PEC target is VM `101`
(`ESUS-TESTE`), but it is stopped. Starting it is a state-changing action and
was not performed.

## Nginx CT Read-Only Check

CT `110` is active and `nginx -t` returned successful syntax validation. The
command also reported a warning for conflicting server name
`pve-01.cpd.internal` on port `80`; this should be reviewed before adding any
new reverse-proxy server block.

Observed listening services in CT `110` include:

- TCP `80` on all IPv4 addresses via nginx.
- TCP `22` via sshd.
- Local mail listener on `127.0.0.1:25` and `[::1]:25`.
- NetBird DNS listener on `100.94.112.69:53`.

## PEC Installer Status

- No staged `eSUS-AB-PEC-*.jar` or `*PEC*.jar` file was found under
  `/var/lib/vz`, `/root`, `/mnt`, or `/srv` on the Proxmox node.
- No local `.downloads` directory exists in the repository workspace.
- The Linux installer acquisition script dry-run resolved the official PEC
  `5.4.37` URL and destination without downloading.

## Blocked Live Actions

These actions remain blocked until explicit approval:

- Start VM `101`.
- Download the PEC `.jar` without `-DryRun`.
- Execute the PEC installer.
- Stop/start/restart e-SUS PEC, PostgreSQL, nginx, CTs, or VMs.
- Restore a database or copy media files.
- Change nginx configuration, firewall, network, disk, swap, or Proxmox guest
  settings.
