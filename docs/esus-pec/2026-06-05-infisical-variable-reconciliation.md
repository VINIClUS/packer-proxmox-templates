# e-SUS PEC Infisical Variable Reconciliation

## Scope

Reconciled the e-SUS PEC Infisical project `esus-pec`, environment `dev`, using the writable folder layout:

```text
/test/InstallationConfig
```

The older documented `/esus-pec/test` paths returned `404` and were not used. The `/test` folder listed as empty, but the current token could not create missing runtime variables there reliably, so CT `133` variables were consolidated under `/test/InstallationConfig`.

## Implementation

The reusable sync script is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1
```

It reads Proxmox SSH settings from `config/Proxmox.pkrvars.hcl`, reads CT `133` database credentials from `/opt/e-SUS/webserver/config/credenciais.txt`, reuses the first-run installer credential as the current admin credential, and reconciles expected variables in Infisical.

Values were not printed to the console, Git, or documentation.

## Path Ownership

Runtime credentials now live in `/test/InstallationConfig` with the rest of the CT `133` installation state:

- `ESUS_PEC_DB_HOST`
- `ESUS_PEC_DB_PORT`
- `ESUS_PEC_DB_NAME`
- `ESUS_PEC_DB_USER`
- `ESUS_PEC_DB_PASSWORD`
- `ESUS_PEC_ADMIN_USERNAME`
- `ESUS_PEC_ADMIN_PASSWORD`
- `ESUS_PEC_SMTP_ENABLED`
- `ESUS_PEC_SMTP_HOST`
- `ESUS_PEC_SMTP_PORT`
- `ESUS_PEC_SMTP_USERNAME`
- `ESUS_PEC_SMTP_PASSWORD`
- `ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD`
- `ESUS_PEC_RESTORE_ARCHIVE_PASSWORD`

The same path also stores first-run, TLS, non-secret metadata, and post-install desired state. Examples include `ESUS_PEC_TLS_HTTPS_URL`, `ESUS_PEC_LXC_TEST_HTTPS_URL`, `ESUS_PEC_HORUS_DISABLE_INTERVAL`, and `ESUS_PEC_BASE_UNIFICATION_ENABLED`.

## Reconciliation Result

Before the sync, `/test/InstallationConfig` had only first-run and TLS variables. The sync filled missing runtime and installation configuration variables into the same path. No variables were deleted because no existing Infisical key was outside the allowlist.

Validation targets:

```text
expectedRuntimeCount=14
expectedInstallationCount=49
totalKeysAfterSync=62
initialCreatedCount=44
smtpOptionalCreatedCount=3
deletedCount=0
postSyncDryRunCreatedCount=0
postSyncDryRunDeletedCount=0
```

## Notes

Empty optional variables remain present as empty values so future automation can distinguish "known but intentionally unset" from "unknown variable name". Automation must still avoid applying optional empty values to PEC.
