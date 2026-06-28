# e-SUS PEC Production Replacement Variable Comparison

## Scope

This report compares the current production PEC at `https://esus.presidenteepitacio.sp.gov.br` with the restored development installation now exposed as `https://esus.vinisantana.com/`. The development upstream remains `http://192.168.1.209:8080`; the production TLS upstream for `esus.presidenteepitacio.sp.gov.br` is `https://192.168.1.253`. The collection used the installation administrator credentials from `.env` (`user_esus_presidenteepitacio` and `password_esus_presidenteepitacio`) without writing credential values to disk or documentation.

Raw sanitized evidence was generated locally at `output/esus-pec-config-comparison/comparison-raw.json` and is intentionally not a tracked artifact because it contains operational UI data.

## Collection Evidence

| Item | Production | Local |
| --- | --- | --- |
| PEC version | `5.4.37` | `5.4.37` |
| Installation type | `PRONTUARIO` | `PRONTUARIO` |
| HTTPS endpoint | `https://esus.presidenteepitacio.sp.gov.br` | `https://esus.vinisantana.com/` |
| Authenticated pages collected | `15` | `15` |
| GraphQL responses captured | `77` | `77` |

Correct active routes observed in PEC 5.4.37:

- CNES import: `/importarCnes`
- Bolsa Familia import: `/importar-bolsa-familia`
- Transmission configuration: `/transmissao/configuracoes`

`/configuracoes/transmissao` returns the PEC "Pagina nao encontrada" screen in both environments and should not be used for automation.

## Installation Configuration Comparison

| Area | Variable / setting | Production | Local | Action |
| --- | --- | --- | --- | --- |
| Runtime info | `govBREnabled` | `true` | `false` | Missing local desired-state variable and implementation check. Add `ESUS_PEC_GOVBR_ENABLED=true` and investigate whether this is controlled by runtime config, license, external service, or build flag. |
| Runtime info | `serverTimezoneOffset` | `-180` | `0` | Fix local runtime timezone before cutover. Add `ESUS_PEC_SERVER_TIMEZONE=America/Sao_Paulo` and validate Java/CT timezone. |
| Connection | Internet | `true` | `true` | No action. Existing `ESUS_PEC_INTERNET_ENABLED` covers desired state. |
| Connection | CADSUS | `true` | `true` | No action. Existing `ESUS_PEC_CADSUS_ENABLED` covers desired state. |
| Connection | Horus | `true` | `true` | No action. Existing `ESUS_PEC_HORUS_ENABLED` covers desired state. |
| Connection | Videochamadas | `true` | `true` | No action. Existing `ESUS_PEC_VIDEOCHAMADAS_ENABLED` covers desired state. |
| Connection | Agenda online | `false` | `false` | No action. Existing `ESUS_PEC_AGENDA_ONLINE_ENABLED` covers desired state. |
| Connection | Prescricao digital | `false` | `false` | No action. Existing assinatura digital variables cover desired state. |
| Security | Password reset period | PEC default | PEC default | No action. Existing `ESUS_PEC_PASSWORD_RESET_PERIOD_MONTHS` covers desired state if this must be pinned. |
| Security | Inactivity timeout | `60` minutes | `60` minutes | No action. Existing `ESUS_PEC_MAX_INACTIVITY_MINUTES` covers desired state. |
| Security | Login attempts | `5` | `5` | No action. Existing `ESUS_PEC_MAX_LOGIN_ATTEMPTS` covers desired state. |
| Servers | Installation name | `Centro de Saude` | `Centro de Saude` | No action. Covered by `ESUS_PEC_INSTALLATION_NAME`. |
| Servers | Installation link | `https://esus.presidenteepitacio.sp.gov.br` | `https://esus.vinisantana.com` | Keep the production link only on the production instance. Development must use `ESUS_PEC_PUBLIC_BASE_URL=https://esus.vinisantana.com`; production TLS uses `ESUS_PEC_PRODUCTION_UPSTREAM_URL=https://192.168.1.253`. |
| Servers | SMTP configured | `false` | `false` | No action unless notifications are later required. |
| Advanced | Concurrent requests | `16`, default enabled | same | No action. Existing concurrent-request variables cover this. |
| Advanced | Citizen search by properties | `true` | `true` | No action. Existing variable covers this. |
| Advanced | CDS property/family registration | `false` | `false` | No action. Existing variable covers this. |
| Base unification | Active send request | `null` | `null` | No action. |
| Base unification | Existing unifications | `0` | `0` | No action. |

## CNES, Bolsa Familia, And Transmission

| Area | Setting / evidence | Production | Local | Missing variable for reproducibility |
| --- | --- | --- | --- | --- |
| CNES | Route availability | `/importarCnes` | `/importarCnes` | `ESUS_PEC_CNES_IMPORT_ROUTE=/importarCnes` |
| Bolsa Familia | Correct route | `/importar-bolsa-familia` | `/importar-bolsa-familia` | `ESUS_PEC_BOLSA_FAMILIA_IMPORT_ROUTE=/importar-bolsa-familia` |
| Bolsa Familia | Latest vigencia | `202402` | `202402` | `ESUS_PEC_BOLSA_FAMILIA_EXPECTED_LATEST_VIGENCIA=202402` |
| Bolsa Familia | Import count | `1` | `1` | `ESUS_PEC_BOLSA_FAMILIA_EXPECTED_IMPORT_COUNT=1` |
| Bolsa Familia | Last import status | `FINALIZADO` | `FINALIZADO` | `ESUS_PEC_BOLSA_FAMILIA_EXPECTED_IMPORT_STATUS=FINALIZADO` |
| Transmission | Link hostname | `esusab.saude.gov.br` | same | `ESUS_PEC_TRANSMISSAO_LINK_HOSTNAME=esusab.saude.gov.br` |
| Transmission | Link name | `Centralizador Nacional` | same | `ESUS_PEC_TRANSMISSAO_LINK_NAME=Centralizador Nacional` |
| Transmission | Link active | `true` | `true` | `ESUS_PEC_TRANSMISSAO_LINK_ACTIVE=true` |
| Transmission | Connection status | `true` | `true` | `ESUS_PEC_TRANSMISSAO_LINK_STATUS_EXPECTED=true` |
| Transmission | Batch generation time | `00:00:00` | `00:00:00` | `ESUS_PEC_TRANSMISSAO_LOTE_PROCESSAMENTO_HORARIO=00:00:00` |
| Transmission | Integration credentials count | `0` | `0` | `ESUS_PEC_TRANSMISSAO_CREDENCIAIS_INTEGRACAO_EXPECTED_COUNT=0` |
| Transmission API credentials | Person type field | `FISICA` default | `FISICA` default | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_PERSON_TYPE=FISICA` |
| Transmission API credentials | Responsible-name field | blank | blank | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_RESPONSIBLE_NAME=` |
| Transmission API credentials | CPF/CNPJ field | blank | blank | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_CPF_CNPJ=` |
| Transmission API credentials | E-mail field | blank | blank | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_EMAIL=` |
| Transmission API credentials | Credential-name field | blank | blank | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_NAME=` |
| Transmission API credentials | Active-only filter | `false` | `false` | `ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_ACTIVE_ONLY=false` |

## Implementation Gaps

1. Add the new non-secret desired-state variables to Infisical under the matching `/test/InstallationConfig/*` subfolders; later mirror to `/prod/InstallationConfig` during the approved cutover.
2. Correct local timezone to `America/Sao_Paulo` and revalidate that `serverTimezoneOffset` returns `-180`.
3. Investigate `govBREnabled=false` on the local installation before replacing production. This is the only functional setting mismatch found in the collected installation configuration.
4. Keep the production public URL in the restored local database for replacement readiness, but validate DNS/TLS before traffic cutover.

## Validation Commands

```powershell
rtk node --check scripts/esus-pec/Collect-EsusPecConfigurationComparison.mjs
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-EsusPecProductionReplacementComparison.ps1
```

