# app e-SUS PEC Source Notes

Source: <https://gemini.google.com/share/bbe9ab81eadb>
Read date: 2026-05-25
Mode: source extraction only; no infrastructure changes were executed.

## Extracted Operational Context

The shared Gemini conversation is about preparing e-SUS PEC on Debian 13 and
handling practical installation and recovery issues observed during setup.

## Source Requirements for Setup.md

| ID | Requirement | Evidence from source conversation | Setup.md impact |
|---|---|---|---|
| APP-REQ-001 | Debian 13 is the current OS context for the e-SUS PEC installation. | User reports using Debian 13 to install e-SUS PEC. | Setup must treat Debian 13 as the app OS unless changed by confirmation. |
| APP-REQ-002 | The e-SUS PEC Java installer may fail without X11 display support. | Installer `.jar` failed with `No X11 DISPLAY variable was set`. | Setup must prefer headless/console installation when supported, and document X11/Xwayland as fallback only. |
| APP-REQ-003 | Avoid depending on Wayland GUI for server setup. | X11 session options were unavailable or ineffective. | Setup must not require GUI access for the operational path. |
| APP-REQ-004 | PostgreSQL client/server tooling is required for database operations. | Conversation covered installing `postgresql` and `postgresql-contrib` on Debian 13. | Setup must include PostgreSQL preflight and version/path discovery. |
| APP-REQ-005 | `.backup` files should usually be restored with `pg_restore`, not `psql`. | Source distinguishes custom PostgreSQL dumps from plain SQL files. | Setup must identify backup format with `file` before selecting restore command. |
| APP-REQ-006 | Password-based PostgreSQL restore must avoid leaking secrets. | Source discusses `-W` and `PGPASSWORD`, warning about shell history. | Setup must prefer interactive prompt or `.pgpass`/protected env handling; never record passwords in docs/logs. |
| APP-REQ-007 | Official e-SUS restore may require stopping the application before database restore. | Source restore flow stops the service before DB changes. | Setup must mark restore as destructive/disruptive and require explicit approval plus backup. |
| APP-REQ-008 | Restore can include both database and media/attachment directories. | Source mentions backup archives containing database plus `galeria`/media files. | Setup must inventory app paths and media directories before restore. |
| APP-REQ-009 | Disk expansion in Proxmox may require guest partition/filesystem growth. | Source covers `growpart`, `resize2fs`, rescan and blocked swap partition cases. | Setup must include storage preflight and avoid partition edits without approved maintenance window. |
| APP-REQ-010 | If partition-based swap blocks expansion, a swapfile may be safer than repartitioning. | Source recommends `/swapfile` when MBR primary partition slots are exhausted. | Setup must document swapfile as the preferred low-risk option after root FS expansion. |

## Non-Destructive Discovery Commands

These commands are safe to include in read-only phases:

```bash
java -version || true
psql --version || true
pg_restore --version || true
lsblk -f
df -hT
free -h
systemctl --type=service --state=running
ss -lntup
find /opt /srv /var/www -maxdepth 3 -type f 2>/dev/null | head -200
```

## Destructive or Disruptive Actions Requiring Explicit Approval

- Stopping e-SUS PEC, WildFly, Tomcat, PostgreSQL, nginx, CTs, VMs, or network services.
- Dropping, recreating, or restoring PostgreSQL databases.
- Editing `pg_hba.conf`, `postgresql.conf`, service units, or app environment files.
- Editing `/etc/fstab`, changing partitions, deleting swap partitions, or creating swapfiles.
- Copying backup media over existing e-SUS PEC media directories.
- Reloading nginx or changing firewall rules.

## Pending Confirmations

- Exact e-SUS PEC version and installer filename.
- Whether the installer supports `-console`.
- Actual service name: `esus`, `wildfly`, `tomcat`, another unit, or manual script.
- PostgreSQL version and whether e-SUS uses bundled or system PostgreSQL.
- Database name, database user, and authentication method.
- Backup file path, type, and whether media files are included.
- Final disk size and desired swap sizing.
