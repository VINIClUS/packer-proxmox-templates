# e-SUS PEC Infisical Variable Reconciliation

## Scope

Reconciled the e-SUS PEC Infisical project `esus-pec`, environment `dev`, using the folder layout:

```text
/test
/test/InstallationConfig
```

The older documented `/esus-pec/test` paths returned `404` and were not used. After token correction, the sync applied successfully to both `/test` and `/test/InstallationConfig`.

## Implementation

The reusable sync script is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1
```

The read-only inventory analyzer is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Analyze-EsusPecInfisicalVariables.ps1
```

The sync reads Proxmox SSH settings from `config/Proxmox.pkrvars.hcl`, reads CT `133` database credentials from `/opt/e-SUS/webserver/config/credenciais.txt`, reuses the first-run installer credential as the current admin credential, recovers installation values that were temporarily placed in `/test`, and reconciles expected variables in Infisical. It now extends the managed allowlist from `config/esus-pec.infisical.env.example`, so later additions such as MinIO, WAL-G, Gov.br OAuth, CNES/PBF import metadata, transmission desired state, and Grafana credentials are preserved. A non-dry-run sync first performs a create/delete probe on each target path so source secrets are not deleted when a destination path is not writable.

Values were not printed to the console, Git, or documentation.

## Path Ownership

`/test` stores runtime credentials and service runtime values:

- `ESUS_PEC_DB_HOST`
- `ESUS_PEC_DB_PORT`
- `ESUS_PEC_DB_NAME`
- `ESUS_PEC_DB_USER`
- `ESUS_PEC_DB_PASSWORD`
- `ESUS_PEC_DB_READONLY_USER`
- `ESUS_PEC_DB_READONLY_PASSWORD`
- `ESUS_PEC_ADMIN_USERNAME`
- `ESUS_PEC_ADMIN_PASSWORD`
- `ESUS_PEC_SMTP_HOST`
- `ESUS_PEC_SMTP_PORT`
- `ESUS_PEC_SMTP_USERNAME`
- `ESUS_PEC_SMTP_PASSWORD`
- `ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD`
- `ESUS_PEC_RESTORE_ARCHIVE_PASSWORD`
- `ESUS_PEC_OBJECT_STORAGE_*`
- `ESUS_PEC_WALG_*`

`/test/InstallationConfig` stores first-run, TLS, non-secret metadata, monitoring references, and post-install desired state. Examples include `ESUS_PEC_TLS_HTTPS_URL`, `ESUS_PEC_LXC_TEST_HTTPS_URL`, `ESUS_PEC_HORUS_DISABLE_INTERVAL`, `ESUS_PEC_BASE_UNIFICATION_ENABLED`, `ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET`, `ESUS_PEC_CNES_IMPORT_OBJECT_KEY`, `ESUS_PEC_BOLSA_FAMILIA_IMPORT_OBJECT_KEY`, and `grafana_token`.

## Reconciliation Result

Before this correction, runtime variables and a small set of installation variables were present in `/test`, and runtime duplicates were also present in `/test/InstallationConfig`. The corrected sync moved ownership to the intended paths, added the read-only database user from `credenciais.txt`, and removed misplaced installation variables, runtime duplicates, and legacy read-only names.

Current validation result:

```text
currentTestSecretCount=53
currentInstallationConfigSecretCount=107
expectedRuntimeCount=53
expectedInstallationCount=107
expectedTotalKeys=160
expectedDuplicateNames=0
expectedMisplacedTestKeys=0
postSyncDryRunCreatedCount=0
postSyncDryRunDeletedCount=0
postSyncDryRunDeletedVariables=[]
secretValuesPrinted=0
```

On 2026-06-21, after the Infisical token was updated, the analyzer found zero duplicate names, zero misplaced variables, and 16 missing `InstallationConfig` names from the tracked `.example` catalog. The corrected sync created those 16 names and deleted no variables. The follow-up analyzer run reported zero missing, zero misplaced, and zero unmanaged names in both managed paths.

## Notes

Empty optional variables remain present as empty values so future automation can distinguish "known but intentionally unset" from "unknown variable name". Automation must still avoid applying optional empty values to PEC.
