# e-SUS PEC Risk, Rollback, and Next Steps

Date: 2026-05-25

## Current Risks

| ID | Risk | Evidence | Severity | Mitigation |
|---|---|---|---|---|
| R1 | Wrong target guest | CT `120` is `infisical`; VM `101` is `ESUS-TESTE` but stopped. | High | Confirm VM `101` is the PEC host before any install or proxy work. |
| R2 | Nginx name conflict | `nginx -t` warns about duplicate `pve-01.cpd.internal` on port `80`. | Medium | Review existing server blocks before adding a PEC virtual host. |
| R3 | Installer not staged | No PEC `.jar` found on node or local workspace. | Medium | Use dry-run first, then approved download into `.downloads/`. |
| R4 | Unknown guest internals | VM `101` is stopped, so Java/PostgreSQL/filesystem state was not inspected. | High | Start VM only in an approved maintenance window or use offline disk inspection after approval. |
| R5 | Restore may be destructive | e-SUS restore may touch DB and media directories. | High | Require backup, hash checks, format detection, and explicit restore approval. |

## Rollback Design

No live changes were applied in this run, so no runtime rollback was required.
Before any approved live step, capture:

- `qm config 101`
- `pct config 110`
- `pct config 120`
- `nginx -t`
- nginx config backup from CT `110`
- VM `101` snapshot or full backup when supported
- database and media backup if PEC restore is planned

Rollback commands must be prepared but not executed until a specific change is
approved. Candidate rollback actions:

```bash
# Restore nginx config backup, then validate.
nginx -t

# Revert Proxmox guest config from captured config if a setting was changed.
qm set 101 <previous-option>
pct set 110 <previous-option>

# Revert a snapshot only after explicit confirmation.
qm rollback 101 <snapshot-name>
```

## Implementation Package

Next implementation should proceed as atomic commits:

1. Confirm target: VM `101` vs another guest.
2. Stage PEC Linux installer with hash evidence, without execution.
3. Inspect guest prerequisites: Java, PostgreSQL tools, disk, filesystem, swap,
   services, and media paths.
4. Build a VM-specific backup and rollback bundle.
5. Execute installer or restore only after approval.
6. Add nginx reverse proxy only after resolving the current server-name warning.
7. Validate from internal network, then from the intended external path.

## Pending Approvals

- Permission to start VM `101`.
- Permission to download the Linux PEC installer locally.
- Maintenance window for any e-SUS service/database restore.
- Domain name and TLS strategy for the PEC reverse proxy.
- Approval to edit and reload nginx in CT `110`.
