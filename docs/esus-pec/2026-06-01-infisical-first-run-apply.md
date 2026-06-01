# e-SUS PEC Infisical First-Run Apply

## Scope

This records the first unattended PEC wizard apply for CT `133 esus-pec-lxc-5437` at `http://192.168.1.209:8080`. VM `101` was not modified. CT `100` NetBird was not modified.

## Infisical Source

Infisical runs in CT `120` at `192.168.1.226:8080`. The project discovered for this workflow is `esus-pec` with slug `esus-pec-z-px-c`.

The operator-provided secrets were found as Infisical folders, not as an environment named `test`. Environments present: `prod`, `staging`, and `dev`. For this test apply, the `dev` environment was used with folder path:

```text
/test/InstallationConfig
```

Required keys confirmed by name only:

- `ESUS_PEC_BASE_URL`
- `ESUS_PEC_INSTALLATION_NAME`
- `ESUS_PEC_INSTALLATION_URL`
- `ESUS_PEC_INSTALLATION_TYPE`
- `ESUS_PEC_INSTALLER_NAME_CIVIL`
- `ESUS_PEC_INSTALLER_CPF`
- `ESUS_PEC_INITIAL_PASSWORD`

No secret values were written to Git or documentation.

## Implementation

`scripts/esus-pec/Invoke-EsusPecFirstRunConfigFromJson.ps1` loads a temporary JSON secret export, sets process-only environment variables, and invokes `Invoke-EsusPecFirstRunConfig.ps1`. It supports `-BaseUrl` so the automation can submit to the reachable CT endpoint while preserving the public installation URL stored in Infisical.

`Invoke-EsusPecFirstRunConfig.ps1` now checks for GraphQL errors in a `Set-StrictMode`-safe way. The previous behavior submitted the mutation successfully but failed afterward when the response had no `errors` property.

## Apply Evidence

Before apply, snapshot `pre-infisical-first-run-apply-20260601` was created on CT `133`.

Validation results:

```text
dry_run_ok
root_http=200
graphql_http=200
graphql_contains_errors=False
ativado=True
linkInstalacaoConfigurado=True
smtpConfigurado=False
internetHabilitada=True
```

`smtpConfigurado=False` is expected because SMTP was not part of the first wizard payload.

## Cleanup

Temporary JSON secret exports and extraction helpers were removed from the local machine, Proxmox host `/tmp`, and Infisical CT `/tmp`. The Proxmox snapshot remains available as a rollback point until manual cleanup is approved.
