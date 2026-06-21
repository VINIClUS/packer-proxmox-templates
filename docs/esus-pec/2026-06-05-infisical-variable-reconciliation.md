# e-SUS PEC Infisical Variable Reconciliation

## Scope

Reconciled the e-SUS PEC Infisical project `esus-pec`, environment `dev`, using the folder layout:

```text
/test
/test/InstallationConfig
/test/InstallationConfig/FirstRun
/test/InstallationConfig/TLS
/test/InstallationConfig/Connectivity
/test/InstallationConfig/Security
/test/InstallationConfig/Municipality
/test/InstallationConfig/Files
/test/InstallationConfig/Advanced
/test/InstallationConfig/GovBrOAuth
/test/InstallationConfig/Importacao
/test/InstallationConfig/ImportacaoCNES
/test/InstallationConfig/ImportacaoBolsaFamilia
/test/InstallationConfig/Transmissao
/test/InstallationConfig/TransmissaoAPI
/test/Monitoring
/test/ObjectStorage
```

The older documented `/esus-pec/test` paths returned `404` and were not used. After token correction, the sync applied successfully to `/test`, `/test/InstallationConfig`, `/test/Monitoring`, and `/test/ObjectStorage`.

## Implementation

The reusable sync script is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1
```

The read-only inventory analyzer is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Analyze-EsusPecInfisicalVariables.ps1
```

The sync reads Proxmox SSH settings from `config/Proxmox.pkrvars.hcl`, reads CT `133` database credentials from `/opt/e-SUS/webserver/config/credenciais.txt`, reuses the first-run installer credential as the current admin credential, and reconciles expected variables in Infisical. It extends the managed allowlist from `config/esus-pec.infisical.env.example`, so later additions such as MinIO, WAL-G, Gov.br OAuth, CNES/PBF import metadata, transmission desired state, and Grafana credentials are preserved. A non-dry-run sync first performs a create/delete probe on each target path so source secrets are not deleted when a destination path is not writable.

Values were not printed to the console, Git, or documentation.

## Path Ownership

`/test` stores PEC runtime credentials:

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

Object storage values live under <code>/test/ObjectStorage</code>:

- `ESUS_PEC_OBJECT_STORAGE_*`
- `ESUS_PEC_WALG_*`

Monitoring values live under <code>/test/Monitoring</code>:

- `ESUS_PEC_POSTGRES_EXPORTER_PASSWORD`
- `grafana_url`
- `grafana_token`

`/test/InstallationConfig` is now the parent for endpoint/functionality folders. The intended ownership is:

- `FirstRun`: installer URL/checksum, first-run wizard values, local CT URLs, and credential-file location.
- `TLS`: certificate PEM, private key PEM, HTTPS URL, fingerprint, SAN, expiration, and TLS termination mode.
- `Connectivity`: internet, CADSUS, Horus, video calls, online agenda, and SMTP desired-state toggles.
- `Security`: digital-signature fields and password/session security policy.
- `Municipality`: municipality and responsible-professional desired state.
- `Files`: PEC file-attachment toggle and directory.
- `Advanced`: concurrent requests, citizen search, CDS family/property registration, base unification, and server timezone.
- `GovBrOAuth`: Gov.br OAuth and native TLS fallback variables.
- `Importacao`: empty grouping folder retained after the folder-creation attempt; no managed secret currently belongs here.
- `ImportacaoCNES`: CNES route, object metadata, and latest import result.
- `ImportacaoBolsaFamilia`: Bolsa Familia route, object metadata, expected vigencia, and latest import result.
- `Transmissao`: transmission link route, centralizer metadata, status, and batch-processing time.
- `TransmissaoAPI`: API credential desired state and the `CredenciaisIntegracaoOld` expected count.

## Reconciliation Result

Before this correction, runtime variables and a small set of installation variables were present in `/test`, and runtime duplicates were also present in `/test/InstallationConfig`. The corrected sync moved ownership to the intended paths, added the read-only database user from `credenciais.txt`, and removed misplaced installation variables, runtime duplicates, and legacy read-only names.

Current validation result:

```text
currentTestSecretCount=15
currentInstallationConfigSecretCount=104
currentMonitoringSecretCount=3
currentObjectStorageSecretCount=38
expectedRuntimeCount=15
expectedInstallationCount=104
expectedMonitoringCount=3
expectedObjectStorageCount=38
expectedTotalKeys=160
expectedDuplicateNames=0
expectedMisplacedTestKeys=0
postSyncDryRunCreatedCount=0
postSyncDryRunDeletedCount=0
postSyncDryRunDeletedVariables=[]
secretValuesPrinted=0
```

On 2026-06-21, after the Infisical token was updated, the analyzer found zero duplicate names, zero misplaced variables, and 16 missing `InstallationConfig` names from the tracked `.example` catalog. The corrected sync created those 16 names and deleted no variables. The follow-up analyzer run reported zero missing, zero misplaced, and zero unmanaged names in both managed paths.

Later on 2026-06-21, the domain migration moved `grafana_url`, `grafana_token`, and `ESUS_PEC_POSTGRES_EXPORTER_PASSWORD` to `/test/Monitoring`; it also moved all `ESUS_PEC_OBJECT_STORAGE_*` and `ESUS_PEC_WALG_*` names to `/test/ObjectStorage`. The sync created 41 destination entries, removed the 41 old-path entries only after destination creation, and the follow-up analyzer reported zero duplicates, zero missing variables, zero misplaced variables, and zero unmanaged variables across all four managed paths.

On 2026-06-21, the transmission settings route `/transmissao/configuracoes` was reviewed again. The "Credenciais para API" area exposes `tipoPessoa`, `nomeResponsavel`, `cpfCnpj`, `email`, `nomeCredencial`, and the active-only filter through `CredenciaisIntegracaoOld`; production and local both had zero existing integration credentials in the collected comparison. The tracked catalog now includes:

```text
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_PERSON_TYPE=FISICA
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_RESPONSIBLE_NAME=
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_CPF_CNPJ=
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_EMAIL=
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_NAME=
ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_ACTIVE_ONLY=false
```

The subfolder migration is implemented in `Sync-EsusPecInfisicalVariables.ps1` and `Analyze-EsusPecInfisicalVariables.ps1`, but the first non-dry-run attempt stopped before moving secrets because the current token returned HTTP `403` for secret creation in `/test/InstallationConfig/FirstRun`. No source secret was deleted.

On 2026-06-21, `scripts/esus-pec/Ensure-EsusPecInfisicalFolders.ps1` was added to create folders without creating or moving secrets. Because the token allows creating only direct children of `/test/InstallationConfig`, the CNES, Bolsa Familia, and transmission API targets were flattened to one-level paths. The folder creation then completed with `missingCount=0`.

Grant create/delete for secrets, not only folders, on all direct `InstallationConfig` child paths before rerunning the non-dry-run sync.

After the token update, a new non-dry-run attempt was deliberately stopped by the sync guard because the token returned HTTP `200` but exposed zero visible secrets under `/test` and under every `InstallationConfig` path. The same token still exposed `/test/Monitoring` with 3 secrets and `/test/ObjectStorage` with 38 secrets, so this is a source-path visibility problem rather than a network failure.

Required local `.env` entries for the Infisical tooling:

```text
infisical_secret_key=<token with read/create/update/delete for the paths below>
INFISICAL_URL=http://192.168.1.226:8080
INFISICAL_WORKSPACE_ID=2c83cfe9-e794-4961-977d-23000ae14461
INFISICAL_PROJECT_SLUG=esus-pec-z-px-c
INFISICAL_ENVIRONMENT=dev
```

Required Infisical secret permissions before the next migration attempt:

```text
/test
/test/InstallationConfig
/test/InstallationConfig/FirstRun
/test/InstallationConfig/TLS
/test/InstallationConfig/Connectivity
/test/InstallationConfig/Security
/test/InstallationConfig/Municipality
/test/InstallationConfig/Files
/test/InstallationConfig/Advanced
/test/InstallationConfig/GovBrOAuth
/test/InstallationConfig/ImportacaoCNES
/test/InstallationConfig/ImportacaoBolsaFamilia
/test/InstallationConfig/Transmissao
/test/InstallationConfig/TransmissaoAPI
```

Do not use `-AllowBootstrapEmptySources` unless the old source secrets were intentionally removed and the operator has confirmed that blank/default bootstrap values are acceptable. The normal migration must preserve existing values by reading the source paths first.

Current blocked validation result:

```text
currentTestSecretCount=15
currentInstallationConfigSecretCount=104
currentMonitoringSecretCount=3
currentObjectStorageSecretCount=38
expectedRuntimeCount=15
expectedInstallationCount=110
expectedMonitoringCount=3
expectedObjectStorageCount=38
expectedDuplicateNames=0
plannedSubpathMigrationCreatedCount=110
plannedSubpathMigrationDeletedCount=104
folderEnsureMissingCount=0
pendingSecretMigrationHttp403=/test/InstallationConfig/FirstRun
postTokenUpdateVisibleTestSecretCount=0
postTokenUpdateVisibleInstallationSecretCount=0
syncGuard=Refusing to sync because /test is readable but has zero visible secrets
secretValuesPrinted=0
```

## Notes

Empty optional variables remain present as empty values so future automation can distinguish "known but intentionally unset" from "unknown variable name". Automation must still avoid applying optional empty values to PEC.

