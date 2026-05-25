# e-SUS PEC Action Classification

Date: 2026-05-25
Purpose: classify the remaining implementation plan before live execution.

## Read-Only Actions

These can be repeated without changing infrastructure state:

- Query Proxmox version, VM/CT lists, storage status, and VM/CT configs.
- Run `nginx -t` in CT `110`.
- Check service active state with `systemctl is-active`.
- List listening sockets with `ss -lntp`.
- Search for staged PEC installers by filename.
- Run `shared/scripts/Get-EsusPecInstaller.ps1 -DryRun`.
- Run local tests under `tests/`.

## Safe Local Changes

These modify only the Git workspace:

- Update Markdown documentation.
- Add or update validation scripts.
- Commit changes.
- Download installer only into ignored `.downloads/` after approval.

## Approval-Gated Changes

These require explicit approval and a rollback point:

- Starting VM `101` to inspect the e-SUS PEC guest.
- Downloading the PEC installer without `-DryRun`.
- Executing `java -jar` or any installer command.
- Creating Proxmox snapshots or backups.
- Editing nginx configuration or reloading nginx.
- Changing firewall, routing, DNS, NetBird, CT/VM config, disk, filesystem, or
  swap.
- Stopping or restarting any app, database, CT, VM, or infrastructure service.

## Current Decision

Continue with read-only validation and documentation only. The next live step is
to start or inspect VM `101`, but that is intentionally blocked until approved.
