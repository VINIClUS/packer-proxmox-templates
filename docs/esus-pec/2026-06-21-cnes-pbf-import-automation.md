# e-SUS PEC CNES And Bolsa Familia Import Automation

## Scope

This run adds reproducible import automation for the two operator-provided files in the repository root:

- `XmlParaESUS31_354130.zip`: CNES import package containing `XmlParaESUS31_354130.xml`.
- `pbf_354130_12026_0.zip`: Bolsa Familia package containing `pbf_354130_12026_0.json`.

The files are first uploaded to MinIO for provenance, then submitted to the local PEC installation at `https://192.168.1.209/` using the PEC 5.4.37 REST upload endpoints discovered from the front-end bundle.

## Implementation

`scripts/esus-pec/Upload-EsusPecImportArtifactToMinio.ps1` uploads any import ZIP to MinIO through CT `134`, reads the MinIO credential from Infisical `/test`, validates SHA-256 and object size, inspects ZIP entries, and writes non-secret metadata to Infisical `/test/InstallationConfig`.

`scripts/esus-pec/Import-EsusPecCnesAndBolsaFamilia.mjs` logs in with the PEC installation administrator credentials, submits multipart uploads, polls GraphQL until each import reaches a final state, and records last-run status metadata in Infisical.

PEC endpoints:

- CNES: `POST /api/cnes/{municipioId}`
- Bolsa Familia: `POST /api/bolsa-familia/importar`

Validation queries:

- `ImportacoesCnes`
- `ImportacoesBolsaFamilia`

## Commands

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Upload-EsusPecImportArtifactToMinio.ps1 -ArtifactFile XmlParaESUS31_354130.zip -ObjectKey imports/cnes/2026/06/XmlParaESUS31_354130.zip -MetadataPrefix ESUS_PEC_CNES_IMPORT
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/esus-pec/Upload-EsusPecImportArtifactToMinio.ps1 -ArtifactFile pbf_354130_12026_0.zip -ObjectKey imports/bolsa-familia/2026/06/pbf_354130_12026_0.zip -MetadataPrefix ESUS_PEC_BOLSA_FAMILIA_IMPORT
rtk node scripts/esus-pec/Import-EsusPecCnesAndBolsaFamilia.mjs --municipality-id 9946
```

## Infisical Variables

The new variables are non-secret operational metadata and belong in `/test/InstallationConfig`.

CNES:

- `ESUS_PEC_CNES_IMPORT_OBJECT_KEY`
- `ESUS_PEC_CNES_IMPORT_SOURCE_FILENAME`
- `ESUS_PEC_CNES_IMPORT_SHA256`
- `ESUS_PEC_CNES_IMPORT_SIZE_BYTES`
- `ESUS_PEC_CNES_IMPORT_UPLOADED_AT`
- `ESUS_PEC_CNES_IMPORT_ZIP_ENTRY_COUNT`
- `ESUS_PEC_CNES_IMPORT_ZIP_ENTRIES`
- `ESUS_PEC_CNES_IMPORT_LAST_RUN_AT`
- `ESUS_PEC_CNES_IMPORT_LAST_STATUS`
- `ESUS_PEC_CNES_IMPORT_LAST_IMPORT_ID`
- `ESUS_PEC_CNES_IMPORT_LAST_PROCESS_ID`
- `ESUS_PEC_CNES_IMPORT_LAST_MUNICIPALITY_ID`

Bolsa Familia:

- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_OBJECT_KEY`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_SOURCE_FILENAME`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_SHA256`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_SIZE_BYTES`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_UPLOADED_AT`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_ZIP_ENTRY_COUNT`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_ZIP_ENTRIES`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_RUN_AT`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_STATUS`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_IMPORT_ID`
- `ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_VIGENCIA`

## Validation

Execution on 2026-06-21 against `https://192.168.1.209/` completed successfully:

| Import | Source file | MinIO object | PEC result |
| --- | --- | --- | --- |
| CNES | `XmlParaESUS31_354130.zip` | `imports/cnes/2026/06/XmlParaESUS31_354130.zip` | import `27`, process `27`, status `CONCLUIDO` |
| Bolsa Familia | `pbf_354130_12026_0.zip` | `imports/bolsa-familia/2026/06/pbf_354130_12026_0.zip` | import `2`, vigencia `202601`, status `FINALIZADO` |

MinIO validation:

| File | Size | SHA-256 | ZIP entry |
| --- | ---: | --- | --- |
| `XmlParaESUS31_354130.zip` | `17666` | `25E02DB44CBB96D477A751072B13A6CDC1B9BCD62D9A40A4758BE5A1FD477EB9` | `XmlParaESUS31_354130.xml` |
| `pbf_354130_12026_0.zip` | `167611` | `A5F06C1CEBF1EB3823715612C7A80C21F59C2A5CA0C4F00C1866205DDBBA81E7` | `pbf_354130_12026_0.json` |

Infisical `/test/InstallationConfig` was updated with object metadata and last-run import status. Secret values were not printed or stored in this document.

Use this repository test after changing the scripts or variable inventory:

```powershell
rtk node --check scripts/esus-pec/Import-EsusPecCnesAndBolsaFamilia.mjs
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-EsusPecCnesPbfImportAutomation.ps1
```
