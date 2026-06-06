# e-SUS PEC Backup Restore Tooling

## Scope

Investigated the backup/restore tooling installed with e-SUS PEC on CT `133` and implemented a reusable restore script for the latest backup stored in MinIO.

No destructive restore was executed during this validation. VM `101` and CT `100` were not modified.

## Installed PEC Tool

The installer ships a GUI wrapper:

```text
/opt/e-SUS/database/tools/backup-postgres.sh
/opt/e-SUS/database/tools/backup-postgres.jar
```

The shell wrapper only checks for root and starts the jar:

```text
/opt/e-SUS/jre/current/bin/java -jar backup-postgres.jar
```

In a headless LXC, the jar starts `br.gov.saude.esus.MainWindow` and fails with `HeadlessException` because it requires Swing/X11. It does not expose a CLI help mode.

## Restore Flow Recovered From the Jar

Class string inspection of `br.gov.saude.esus.restore.RestoreTask` showed the restore process uses the embedded PostgreSQL client tools on port `5433`:

```text
service=e-SUS-PEC.service
pg_restore
psql
createdb
dropdb
target_temp_database=esus_new
final_database=esus
restore_args=-p 5433 -U postgres -1 -Fc -d esus_new -O <backup-file>
```

The official flow stops the e-SUS service, terminates active sessions on database `esus`, recreates `esus_new`, restores the custom-format backup into `esus_new`, drops `esus`, renames `esus_new` to `esus`, and starts the service again.

## Current Backup Validation

Backup object:

```text
bucket=esus-pec-backups
object_key=postgres/2026/05/20260519192557-esus-postgres.backup
size_bytes=1529766316
sha256=A388D0769B5B0907652E3DC325E5FEFD7782A4D8206B070AA8CFF31E5DF3918C
```

Safe validation downloaded the object from MinIO, transferred it temporarily to CT `133`, and ran `pg_restore --list`.

Observed archive metadata:

```text
Archive created at 2026-05-19 19:25:57 UTC
dbname=esus
toc_entries=12486
format=CUSTOM
dumped_from_database_version=9.6.13
dumped_by_pg_dump_version=9.6.13
```

Runtime checks:

```text
postgres_port=127.0.0.1:5433
pg_isready=accepting_connections
e-SUS-PEC.service=active
validation_mode=pg_restore_list_ok
temporary_files_removed=true
```

## Restore Script

Reusable script:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Restore-EsusPecBackupFromMinio.ps1
```

Default mode is non-destructive. It:

- reads MinIO endpoint, bucket, object key, backup access key, expected SHA-256, and expected size from Infisical `/test`;
- downloads the object through CT `134`;
- transfers the backup to the target PEC CT;
- validates SHA-256, size, `pg_restore --list`, PostgreSQL readiness, and `e-SUS-PEC.service`;
- removes temporary backup files unless `-KeepDownloadedBackup` is provided.

To apply a destructive restore on a disposable or approved target:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Restore-EsusPecBackupFromMinio.ps1 -Apply -ConfirmDestructiveRestore
```

When applying, the script creates a Proxmox snapshot before modifying the database unless `-SkipSnapshot` is passed.

## Safety Notes

- Do not run `-Apply` against VM `101`.
- Prefer testing on a disposable PEC CT cloned from the template or rebuilt from automation.
- Confirm the backup object key and SHA-256 before restore.
- Keep the MinIO backup object immutable/versioned; do not rely on the local temporary copy.
- The script intentionally refuses `-Apply` unless `-ConfirmDestructiveRestore` is also present.
