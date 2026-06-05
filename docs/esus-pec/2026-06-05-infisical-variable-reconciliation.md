# e-SUS PEC Infisical Variable Reconciliation

## Scope

Prepared reconciliation for the e-SUS PEC Infisical project `esus-pec`, environment `dev`, using the target folder layout:

```text
/test
/test/InstallationConfig
```

The older documented `/esus-pec/test` paths returned `404` and were not used. The current token can read both target paths, but non-dry-run apply is blocked until the token can create and delete secrets directly at `/test`.

## Implementation

The reusable sync script is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1
```

It reads Proxmox SSH settings from `config/Proxmox.pkrvars.hcl`, reads CT `133` database credentials from `/opt/e-SUS/webserver/config/credenciais.txt`, reuses the first-run installer credential as the current admin credential, and reconciles expected variables in Infisical. A non-dry-run sync first performs a create/delete probe on each target path so source secrets are not deleted when a destination path is not writable.

Values were not printed to the console, Git, or documentation.

## Path Ownership

`/test` stores runtime credentials:

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

`/test/InstallationConfig` stores first-run, TLS, non-secret metadata, and post-install desired state. Examples include `ESUS_PEC_TLS_HTTPS_URL`, `ESUS_PEC_LXC_TEST_HTTPS_URL`, `ESUS_PEC_HORUS_DISABLE_INTERVAL`, and `ESUS_PEC_BASE_UNIFICATION_ENABLED`.

## Reconciliation Result

Before this correction, runtime variables had been consolidated under `/test/InstallationConfig`. The corrected sync prepares runtime variables for `/test`, adds the read-only database user from `credenciais.txt`, and removes duplicate runtime variables from `/test/InstallationConfig` after the runtime path is writable.

Current validation result:

```text
currentTestSecretCount=0
currentInstallationConfigSecretCount=62
nonDryRunBlockedBy=/test create/delete permission
secretsMoved=0
secretValuesPrinted=0
```

Target validation after the Infisical token is fixed:

```text
expectedRuntimeCount=15
expectedInstallationCount=49
expectedTotalKeys=64
expectedDuplicateNames=0
postSyncDryRunCreatedCount=0
postSyncDryRunDeletedCount=0
```

## Notes

Empty optional variables remain present as empty values so future automation can distinguish "known but intentionally unset" from "unknown variable name". Automation must still avoid applying optional empty values to PEC.
