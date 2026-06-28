# Packer Proxmox Templates

Infraestrutura como codigo para construir, validar e documentar templates
reprodutiveis no Proxmox VE com HashiCorp Packer e scripts operacionais em
PowerShell/Bash.

O objetivo do repositorio e manter imagens e rotinas administrativas
auditaveis, imutaveis e repetiveis. Alteracoes em scripts, backups, restores,
jobs, agendamentos ou variaveis operacionais devem sair acompanhadas da
documentacao correspondente no mesmo commit.

## Estrutura

```text
config/                 exemplos de variaveis e configuracao local
docs/                   runbooks, relatorios, credenciais e templates
docs/_templates/        modelos obrigatorios para documentacao operacional
linux/<distro>/         templates e scripts Cloud-Init Linux
shared/scripts/         automacoes reutilizaveis entre sistemas
scripts/                rotinas administrativas e integracoes
tests/                  validacoes estaticas e preflights seguros
windows/win11-24h2/     template Windows 11 24H2 com Cloudbase-Init
```

Arquivos com valores reais, como `config/Proxmox.pkrvars.hcl`, `.env` e
credenciais locais, devem permanecer fora do git.

## Comandos principais

Use sempre `rtk` como prefixo dos comandos neste workspace.

```powershell
rtk packer fmt -check -diff windows\win11-24h2
rtk packer init windows\win11-24h2
rtk packer validate -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-WindowsTemplate.ps1
```

Para rotinas operacionais especificas, consulte o runbook do dominio em
`docs/` antes de executar scripts reais.

## Documentacao operacional

O padrao oficial esta em:

- `AGENTS.md`, secao `Operational Documentation Standard`;
- `.agents/skills/documentar-operacao/SKILL.md`;
- `docs/_templates/`;
- `docs/README.md`.

Use portugues brasileiro operacional para runbooks locais, comandos exatos com
`rtk`, criterios de aceite verificaveis, rollback preservando dados e evidencia
de validacao. Nunca registre senhas, tokens, chaves privadas ou dados sensiveis.

## Seguranca

- Trate templates como imutaveis: reconstrua em vez de editar manualmente.
- Use HCL2 para Packer; nao crie templates JSON legados.
- Declare variaveis em arquivos `.pkr.hcl` e documente exemplos rastreados.
- Atualize `.example` e documentacao quando um segredo ou variavel mudar.
- O host `192.168.1.253` / `esus.presidenteepitacio.sp.gov.br` e producao
  e deve ser tratado como leitura por padrao, salvo autorizacao explicita.
