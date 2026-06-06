# e-SUS PEC WAL-G Backup Policy

## Scope

Configured WAL-G on CT `133` for the restored e-SUS PEC PostgreSQL database and MinIO bucket `esus-pec-backups`.

References used:

- WAL-G PostgreSQL docs: `backup-push`, `wal-push`, `wal-verify`, and PostgreSQL env variables.
- WAL-G storage docs: `WALG_S3_PREFIX`, `AWS_ENDPOINT`, `AWS_S3_FORCE_PATH_STYLE`, and MinIO CA support.
- PostgreSQL continuous archiving docs: `archive_mode`, `archive_command`, and `wal_level`.

## Policy

- Full backups: weekly, Sundays at `02:00:00 America/Sao_Paulo` via `esus-pec-walg-full-backup.timer`.
- Retention: keep `4` full backup chains with `wal-g delete retain FULL 4 --confirm`.
- Incremental layer: continuous WAL archiving through PostgreSQL `archive_command`.
- Storage target: `s3://esus-pec-backups/wal-g/ct133`.
- Credentials: WAL-G reuses the limited MinIO backup access key from Infisical `/test`; PostgreSQL password is read from `/opt/e-SUS/webserver/config/credenciais.txt` and stored only in `/etc/esus-pec/walg.env` on CT `133`.

## Installed Files

```text
/usr/local/bin/wal-g
/usr/local/bin/esus-pec-walg-wal-push
/usr/local/bin/esus-pec-walg-full-backup
/etc/esus-pec/walg.env
/etc/esus-pec/minio-ca.pem
/etc/systemd/system/esus-pec-walg-full-backup.service
/etc/systemd/system/esus-pec-walg-full-backup.timer
/var/log/esus-pec-walg/full-backup.log
```

## PostgreSQL Settings

```text
wal_level = replica
archive_mode = on
archive_timeout = '60s'
archive_command = '/usr/local/bin/esus-pec-walg-wal-push %p'
```

`postgresql.conf` was backed up once as:

```text
/opt/e-SUS/database/current/data/postgresql.conf.pre-walg
```

## Validation Evidence

Restore and migration:

```text
restored_backup=postgres/2026/05/20260519192557-esus-postgres.backup
restored_sha256=A388D0769B5B0907652E3DC325E5FEFD7782A4D8206B070AA8CFF31E5DF3918C
restored_database=esus
restored_tables=1101
restored_size=18 GB
database_version_migrated=5.4.36_to_5.4.37
https_status=200
```

WAL-G:

```text
wal_g_version=v3.0.8
initial_full_backup=base_0000000100000000000000E5
archive_failed_count=0
wal_verify_integrity=OK
timer_next_run=Sun 2026-06-07 02:00:00 America/Sao_Paulo
```

## Operations

Validate configuration without applying:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Configure-EsusPecWalGBackups.ps1
```

Apply configuration:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Configure-EsusPecWalGBackups.ps1 -Apply
```

Run a manual full backup:

```powershell
rtk ssh -i C:\Users\Vinicius\.ssh\id_ed25519 root@192.168.1.149 "pct exec 133 -- systemctl start esus-pec-walg-full-backup.service"
```

Check integrity:

```bash
set -a
. /etc/esus-pec/walg.env
set +a
wal-g backup-list
wal-g wal-verify integrity
```

## Notes

- Object lock/versioning remains handled by MinIO.
- Rotation is chain-aware: `retain FULL 4` keeps four full backups and the dependent WAL needed by those chains.
- Do not delete `/etc/esus-pec/walg.env`; it contains operational secrets and must not be copied into this repository.
