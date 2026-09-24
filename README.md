# Packer Proxmox Templates

Templates de maquina virtual reprodutiveis para o Proxmox VE.

Em vez de montar e ajustar VMs manualmente, este repositorio descreve em codigo
como cada template e construido. Assim qualquer pessoa consegue recriar a mesma
imagem, revisar o que mudou e descartar um template antigo sem medo.

## Templates disponiveis

| Template | Como e construido | VMID / nome padrao | Documentacao |
|---|---|---|---|
| Windows 11 24H2 | Packer instala a partir da ISO, aplica VirtIO, Cloudbase-Init e Sysprep | `9101` / `tpl-win11-24h2` | [runbook](docs/windows-win11-24h2-build-runbook.md) |
| Debian 13 | Script importa a imagem oficial `genericcloud` e anexa drive cloud-init | `9200` / `tpl-debian-13-cloudinit` | [README](linux/debian-13-cloudinit/README.md) |
| AlmaLinux 10 | Script importa a imagem oficial `GenericCloud` | `9201` / `tpl-almalinux-10-cloudinit` | [README](linux/almalinux-10-cloudinit/README.md) |
| Ubuntu 26.04 LTS | Script importa a imagem oficial de nuvem | `9202` / `tpl-ubuntu-26-04-cloudinit` | [README](linux/ubuntu-26.04-cloudinit/README.md) |

Os templates Linux nao passam por instalacao via ISO: usam as imagens de nuvem
publicadas por cada distribuicao, importadas no Proxmox com `qm` via SSH. O
Windows usa HashiCorp Packer (HCL2) com instalacao desassistida.

## Estrutura

```text
config/                 exemplo de configuracao do Proxmox (o arquivo real fica fora do git)
linux/<distro>/         script de criacao, variaveis de exemplo e README de cada distro
windows/win11-24h2/     template Packer, arquivos de instalacao desassistida e scripts
shared/scripts/         logica comum aos templates cloud-init
tests/                  validacoes estaticas e preflights de conexao com o Proxmox
docs/                   runbooks, relatorios de build e modelos de documentacao
```

## Antes de comecar

Voce precisa de:

- acesso a API do Proxmox com um token dedicado;
- acesso SSH ao node do Proxmox (necessario para os templates Linux);
- [Packer](https://developer.hashicorp.com/packer) instalado (para o Windows);
- PowerShell 7 (`pwsh`) ou Windows PowerShell.

Copie o exemplo de configuracao e preencha com os valores do seu ambiente:

```powershell
Copy-Item config\Proxmox.pkrvars.hcl.example config\Proxmox.pkrvars.hcl
```

`config/Proxmox.pkrvars.hcl` e `.env` ficam fora do git. Nunca faca commit de
tokens, senhas ou chaves.

Para confirmar que a configuracao consegue falar com o Proxmox:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-ProxmoxPreflight.ps1
```

## Como construir

### Windows 11 24H2

```powershell
packer init windows\win11-24h2
packer validate -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
packer build -var-file="config\Proxmox.pkrvars.hcl" windows\win11-24h2
```

O passo a passo completo, com pre-requisitos e validacao, esta no
[runbook do Windows 11](docs/windows-win11-24h2-build-runbook.md).

### Linux (Debian, AlmaLinux, Ubuntu)

Cada distro tem seu proprio script. Exemplo com Debian 13:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File linux\debian-13-cloudinit\scripts\New-DebianCloudInitTemplate.ps1
```

Adicione `-Force` para substituir um template existente com o mesmo VMID.

## Validacao

Os scripts em `tests/` podem ser rodados antes de qualquer build:

| Script | O que verifica |
|---|---|
| `Test-ProxmoxPreflight.ps1` | Configuracao local preenchida e API do Proxmox acessivel |
| `Get-ProxmoxNodes.ps1`, `Get-ProxmoxIsoInventory.ps1` | Lista nodes e ISOs visiveis para o token |
| `Validate-WindowsTemplate.ps1` | Arquivos e variaveis do template Windows |
| `Validate-*CloudInitTemplate.ps1` | Variaveis e pre-requisitos de cada template Linux |
| `Test-CloudInitTemplateScripts.ps1` | Estrutura dos scripts de criacao cloud-init |
| `Validate-DocumentationStandard.ps1` | Padrao minimo da documentacao operacional |

Para o Windows, `packer fmt -check` e `packer validate` tambem devem passar.

## O que nao fica aqui

Este repositorio cuida apenas dos templates. Outros dominios foram movidos para
repositorios proprios:

- **e-SUS PEC** (bootstrap, monitoramento, backups WAL-G/MinIO):
  [`esus-pec-bootstrap`](https://github.com/VINIClUS/esus-pec-bootstrap).
- **SIHA NAS** (Samba, unidade `S:`, sistemas DATASUS): `sus-siha-bootstrap`.
- **Configuracao das VMs criadas** a partir destes templates: `infra-ansible`.

## Boas praticas

- Templates sao imutaveis: para mudar algo, altere o codigo e reconstrua.
- Mudancas em scripts ou rotinas operacionais vao junto com a documentacao
  correspondente, no mesmo commit.
- O servidor de producao do e-SUS PEC (`192.168.1.253`) nao e alterado a partir
  deste repositorio.

## Mais documentacao

- [`docs/README.md`](docs/README.md): mapa dos runbooks e relatorios de build.
- [`docs/_templates/`](docs/_templates/): modelos para documentacao operacional.
- [`AGENTS.md`](AGENTS.md): regras detalhadas para contribuicoes e agentes de IA.
