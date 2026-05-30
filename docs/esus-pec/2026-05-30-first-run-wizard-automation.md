# e-SUS PEC First-Run Wizard Automation

## Scope

This documents the first-run web wizard observed on CT `133 esus-pec-lxc-5437` at `http://192.168.1.209:8080/`. The PEC service was kept in first-run state; a Proxmox snapshot/rollback probe was used to capture the final request without committing synthetic data.

## Wizard Steps And Variables

### Step 1: Identificar instalação

Visible required fields:

- `ESUS_PEC_INSTALLATION_NAME`: UI label `Nome da instalação`.
- `ESUS_PEC_INSTALLATION_URL`: UI label `Link da minha instalação`. PEC normalizes a bare host to `http://...` and validates the address during final submission.
- `ESUS_PEC_INSTALLATION_TYPE`: UI label `Recursos disponíveis na instalação`; valid values are `PRONTUARIO` or `CENTRALIZADORA`.

### Step 2: Cadastrar instalador

Required fields used by the final mutation:

- `ESUS_PEC_INSTALLER_NAME_CIVIL`: UI label `Nome civil`.
- `ESUS_PEC_INSTALLER_CPF`: UI label `CPF`; normalized to 11 digits and also becomes the disabled `Usuário`.
- `ESUS_PEC_INITIAL_PASSWORD`: UI labels `Senha` and `Confirmação de senha`.

Observed optional UI fields not sent in the minimal payload when left blank:

- `Nome social`
- `CNS`
- `Data de nascimento`
- `Sexo`
- `Conselho de classe`
- `Estado emissor`
- `Registro no conselho de classe`
- `E-mail`
- `Telefone`

Password rules shown by the UI:

- Minimum 8 and maximum 20 characters.
- At least one letter and one number.
- Must not contain personal data such as birth date, CPF, CNS, or name.
- May use letters, numbers, and special characters.
- Case-sensitive.

### Step 3: Finalizar instalação

This page shows recommendations to review connection settings and municipal activation after the first login. The `Finalizar` button submits the GraphQL mutation.

## Captured GraphQL Contract

Endpoint:

```text
POST /api/graphql
```

Operation:

```graphql
mutation Instalar($input: InstalacaoInput!) {
  instalar(input: $input)
}
```

Minimal input shape:

```json
{
  "dadosInstalacao": {
    "linkInstalacao": "https://example.org",
    "nomeInstalacao": "Example Installation"
  },
  "tipoInstalacao": "PRONTUARIO",
  "novaSenha": "[REDACTED]",
  "profissional": {
    "nomeCivil": "Example Operator",
    "cpf": "00000000000",
    "endereco": null
  }
}
```

Synthetic probe result: PEC rejected `http://teste.local` with `Não foi possível validar este endereço. Tente novamente mais tarde`, confirming that a reachable/valid installation URL is required before unattended apply.

## Automation Script

Script:

```powershell
scripts/esus-pec/Invoke-EsusPecFirstRunConfig.ps1
```

Dry-run example:

```powershell
$env:ESUS_PEC_BASE_URL = "http://192.168.1.209:8080"
$env:ESUS_PEC_INSTALLATION_NAME = "Example Installation"
$env:ESUS_PEC_INSTALLATION_URL = "https://example.org"
$env:ESUS_PEC_INSTALLATION_TYPE = "PRONTUARIO"
$env:ESUS_PEC_INSTALLER_NAME_CIVIL = "Example Operator"
$env:ESUS_PEC_INSTALLER_CPF = "00000000000"
$env:ESUS_PEC_INITIAL_PASSWORD = "ChangeMe2026!"
./scripts/esus-pec/Invoke-EsusPecFirstRunConfig.ps1
```

Apply example:

```powershell
./scripts/esus-pec/Invoke-EsusPecFirstRunConfig.ps1 -Apply
```

The script does not print the password in dry-run output. Real values belong in Infisical under `/esus-pec/test-lxc` or the approved production path.

## Validation And Rollback

Before `-Apply`, validate:

```bash
curl -s -o /dev/null -w 'http_code:%{http_code}\n' http://192.168.1.209:8080/
```

Expected: `http_code:200`.

Rollback for test probes:

```bash
pct snapshot 133 pre-first-run-probe
pct rollback 133 pre-first-run-probe
pct start 133
```

Remove the snapshot after the probe is no longer needed:

```bash
pct delsnapshot 133 pre-first-run-probe
```
