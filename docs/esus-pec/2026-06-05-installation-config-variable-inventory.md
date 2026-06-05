# e-SUS PEC Installation Configuration Variable Inventory

## Scope

This inventory was collected from `http://192.168.1.209:8080/configuracoes/instalacao` after logging in as the PEC installer role. No PEC settings were changed. Secret values were not copied to Git or documentation.

Use Infisical project `esus-pec`, environment `dev`, folder `/test/InstallationConfig` for test automation inputs unless a future runbook promotes the same names to production.

## Deduplication Rules

- Reuse `ESUS_PEC_INSTALLATION_NAME` and `ESUS_PEC_INSTALLATION_URL` for the Servers tab. Do not add separate server-name or server-link variables.
- Reuse existing SMTP credentials: `ESUS_PEC_SMTP_HOST`, `ESUS_PEC_SMTP_PORT`, `ESUS_PEC_SMTP_USERNAME`, and `ESUS_PEC_SMTP_PASSWORD`.
- Keep first-run identity variables (`ESUS_PEC_INSTALLER_CPF`, `ESUS_PEC_INSTALLER_NAME_CIVIL`, `ESUS_PEC_INITIAL_PASSWORD`) separate from ongoing installation configuration.
- Prefer stable PEC IDs in automation where the UI combobox requires a selected entity.

## Variable Inventory

| Tab | Variable | Purpose | GraphQL evidence |
| --- | --- | --- | --- |
| Conexao | `ESUS_PEC_INTERNET_ENABLED` | Desired internet integration state. | `AlternarConexaoInternet(habilitado)` |
| Conexao | `ESUS_PEC_CADSUS_ENABLED` | Desired CADSUS state. | `AlterarCadsus(alterarCadsusInput)` |
| Conexao | `ESUS_PEC_CADSUS_DISABLE_INTERVAL` | Temporary disable interval, when disabled. | `intervalo` |
| Conexao | `ESUS_PEC_HORUS_ENABLED` | Desired Horus state. | `AlterarHorus(alterarHorusInput)` |
| Conexao | `ESUS_PEC_HORUS_DISABLE_INTERVAL` | Temporary disable interval, when disabled. | `intervalo` |
| Conexao | `ESUS_PEC_VIDEOCHAMADAS_ENABLED` | Desired video call state. | `AlterarVideochamada(input)` |
| Conexao | `ESUS_PEC_AGENDA_ONLINE_ENABLED` | Desired online schedule state. | `AtivarAgendaOnline`, `DesativarAgendaOnline` |
| Conexao | `ESUS_PEC_ASSINATURA_DIGITAL_ENABLED` | Desired digital signature state. | `AlterarConfiguracaoPrescricaoDigital(input)` |
| Conexao | `ESUS_PEC_ASSINATURA_DIGITAL_LOGIN` | Digital signature login. | `usuario` |
| Conexao | `ESUS_PEC_ASSINATURA_DIGITAL_PASSWORD` | Digital signature password. | `senha` |
| Seguranca | `ESUS_PEC_PASSWORD_RESET_PERIOD_MONTHS` | Password rotation period. | `AlterarPeriodoRedefinicaoSenha(periodo)` |
| Seguranca | `ESUS_PEC_MAX_INACTIVITY_MINUTES` | Session inactivity timeout. | `AlterarPeriodoInatividade(periodo)` |
| Seguranca | `ESUS_PEC_MAX_LOGIN_ATTEMPTS` | Login lockout attempts. | `AlterarNumeroTentativasLogin(tentativas)` |
| Seguranca | `ESUS_PEC_FORCE_PASSWORD_RESET_ON_NEXT_LOGIN` | Whether to force all users to reset passwords. | `ForcarRedefinirSenhas` |
| Servidores | `ESUS_PEC_SMTP_ENABLED` | Desired SMTP state. | `AlterarServidorSMTP`, `DesabilitarConexaoSMTP` |
| Servidores | `ESUS_PEC_SMTP_FROM_EMAIL` | Sender address when not reusing SMTP login. | `email` |
| Servidores | `ESUS_PEC_SMTP_USE_LOGIN_AS_SENDER` | UI checkbox "Usar como e-mail remetente". | `emailRemetente` maps `email=usuario` |
| Municipios | `ESUS_PEC_MUNICIPALITY_ID` | Municipality selected in the combobox. | `MunicipioResponsavelInput` |
| Municipios | `ESUS_PEC_RESPONSIBLE_PROFESSIONAL_ID` | Responsible professional selected in the combobox. | `MunicipioResponsavelInput` |
| Municipios | `ESUS_PEC_MUNICIPAL_RESPONSIBLE_ENABLED` | Desired active state for the relationship. | `AtualizarMunicipioResponsavel` |
| Anexo | `ESUS_PEC_FILE_ATTACHMENTS_ENABLED` | Desired attachment feature state. | `AlterarConfiguracaoAnexoArquivos(input)` |
| Anexo | `ESUS_PEC_FILE_ATTACHMENTS_DIRECTORY` | Server-side attachment directory. | `diretorio` |
| Avancadas | `ESUS_PEC_CONCURRENT_REQUESTS_USE_DEFAULT` | Leave PEC default performance value enabled. | UI checkbox only |
| Avancadas | `ESUS_PEC_CONCURRENT_REQUESTS` | Explicit simultaneous request count. | `AlterarQtdRequisicoes(qtdRequisicoesSimultaneas)` |
| Avancadas | `ESUS_PEC_CITIZEN_SEARCH_BY_PROPERTIES_ENABLED` | Enables citizen search by field/property. | `AlterarBuscaCidadaoPorPropriedades` |
| Avancadas | `ESUS_PEC_CDS_PROPERTY_FAMILY_REGISTRATION_ENABLED` | Enables property/family registrations via CDS. | `AlterarConfiguracaoCadastroDomiciliarViaCds` |
| Unificacao | `ESUS_PEC_BASE_UNIFICATION_ENABLED` | Desired base-unification state. | pending HTTPS validation |
| Unificacao | `ESUS_PEC_BASE_UNIFICATION_MODE` | `SEND_TO_CENTRAL` or `RECEIVE_FROM_LOCAL`. | `unificacaoBaseAtiva` observed |

## Current Observations

- Conexao: internet was enabled; CADSUS enabled; Horus disabled indefinitely; video calls disabled; online schedule disabled; digital signature disabled.
- Seguranca: defaults shown were 6 months for password reset, 1 hour for inactivity, and 5 login attempts.
- Servidores: installation name and link were populated; SMTP showed unsuccessful connection and was not configured.
- Municipios: no records were listed.
- Unificacao de base: credential management was blocked because the session used HTTP; collect HTTPS-only fields after TLS is available.

## Implementation Notes

Future automation should call PEC GraphQL with a dry-run mode first, then apply only variables explicitly present in Infisical. Boolean variables should be idempotent by reading the current query state before mutation. Do not submit `GerarChaveAtivacaoAgendaOnline` or `ForcarRedefinirSenhas` unless their matching variables are explicitly set to `true`.
