# SIHA NAS

## Objetivo

O `siha-nas` e um container Debian LXC unprivileged para servir arquivos do
faturamento SUS/SIHA via Samba para a VM Windows 11 `SIHA`. O acesso principal
e `\\siha-nas\SIHA`, sugerido como unidade `S:` no Windows.

Ele existe para manter remessas, retornos, protocolos, backups, instaladores e
documentacao operacional fora do disco da VM Windows, com estrutura
compreensivel daqui a dois anos ou mais.

## O que guardar

- Remessas enviadas ao Ministerio da Saude.
- Retornos, protocolos e recibos.
- Backups dos sistemas de faturamento.
- Instaladores oficiais, utilitarios e hashes.
- Documentacao operacional e relatorios de auditoria.
- Manifestos, indices anuais e hashes SHA256.

## O que nao guardar

- Senhas, tokens, chaves privadas ou credenciais em texto puro.
- Arquivos pessoais sem relacao com faturamento SUS.
- Temporarios, caches, downloads sem origem conhecida.
- Dados sensiveis desnecessarios para o processo de faturamento.

## Topologia

- Container: `siha-nas`
- Tipo: Debian LXC unprivileged
- Servico: Samba/SMB
- Dados internos: `/dados/siha`
- Share principal: `\\siha-nas\SIHA`
- Unidade sugerida: `S:`
- Grupo: `siha_faturamento`
- Usuario inicial: `siha_user`

O Samba e instalado somente dentro do LXC. Nao instale Samba no host Proxmox e
nao converta o container para privileged.

## Decisao sobre compartilhamentos

A solucao cria tres shares:

- `[SIHA]`: share principal, apontando para `/dados/siha`.
- `[SIHA_BACKUPS]`: atalho para `/dados/siha/03_BACKUPS_SISTEMAS`.
- `[SIHA_ARQUIVO]`: apontando para `/dados/siha/90_ARQUIVO_FECHADO`, em modo
  somente leitura para reduzir alteracoes acidentais no arquivo fechado.

O share principal continua existindo porque a operacao no Windows precisa ser
simples. Os shares adicionais sao conveniencia e protecao operacional, nao uma
fronteira de seguranca completa: usuarios com escrita em `[SIHA]` ainda podem
alterar subpastas conforme permissoes do filesystem.

## Provisionamento

Escolha um CTID livre e um template Debian disponivel no Proxmox. O comando
abaixo mostra o que seria executado:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Provision-SihaNas.ps1 -TargetCtid 7010 -DebianTemplate "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" -CreateContainer -StartContainer -DryRun
```

Execucao real, ainda sem senha Samba embutida:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Provision-SihaNas.ps1 -TargetCtid 7010 -DebianTemplate "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" -CreateContainer -StartContainer
```

Para definir a senha inicial de `siha_user` de forma interativa, sem gravar no
repositorio:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Provision-SihaNas.ps1 -TargetCtid 7010 -StartContainer -SetInitialSambaPassword
```

A senha nao e passada como argumento de linha de comando. O provisionador usa
arquivo temporario restrito e remove o material temporario ao final.

Se o container ja existir, o script valida `hostname: siha-nas` e
`unprivileged: 1` antes de alterar qualquer coisa.

## Criar e trocar senha Samba

Dentro do container:

```bash
smbpasswd -a siha_user
smbpasswd -e siha_user
smbpasswd siha_user
```

Nao registre a senha em scripts, docs, tickets ou chat.

## Adicionar usuario

```bash
useradd --system --no-create-home --shell /usr/sbin/nologin --gid siha_faturamento nome_usuario
smbpasswd -a nome_usuario
smbpasswd -e nome_usuario
```

Para usuario Linux existente:

```bash
usermod -a -G siha_faturamento nome_usuario
smbpasswd -a nome_usuario
```

## Remover acesso

```bash
smbpasswd -d nome_usuario
gpasswd -d nome_usuario siha_faturamento
```

## Validar Samba

```bash
testparm -s /etc/samba/smb.conf
systemctl status smbd --no-pager
smbclient -L //127.0.0.1 -U siha_user
smbclient //127.0.0.1/SIHA -U siha_user -c 'ls'
```

## Acesso pela VM Windows

Execute na VM Windows 11 `SIHA`:

```powershell
PowerShell -ExecutionPolicy Bypass -File scripts\windows\mapear-siha-nas.ps1
```

O script testa TCP 445 e mapeia `S:` para `\\siha-nas\SIHA`. Se credenciais
forem solicitadas, use um usuario Samba autorizado.

## Estrutura

```text
/dados/siha
  00_LEIA-ME
  01_REMESSAS_MS
  02_RETORNOS_MS
  03_BACKUPS_SISTEMAS
  04_INSTALADORES_E_UTILITARIOS
  05_DOCUMENTACAO_OPERACIONAL
  90_ARQUIVO_FECHADO
  91_ARQUIVO_COMPACTADO
  98_RELATORIOS_DE_AUDITORIA
  99_MANIFESTOS_HASHES
```

Cada pasta recebe `.README.txt` com finalidade, exemplos, o que nao salvar,
responsavel, retencao e como localizar arquivos antigos.

## Indice e hashes

Gerar indice de 2026:

```bash
gerar-indice-siha.sh --ano 2026 --base /dados/siha --output /dados/siha/99_MANIFESTOS_HASHES/indice_2026.csv
```

Dry-run:

```bash
gerar-indice-siha.sh --dry-run --ano 2026
```

O dry-run do indice nao grava o CSV final.

## Arquivamento

Relatorio mensal padrao, sem compactar:

```bash
arquivar-antigos-siha.sh --base /dados/siha --older-than-days 730 --report-only
```

Dry-run:

```bash
arquivar-antigos-siha.sh --dry-run --year 2024 --format zip
```

O dry-run do arquivamento nao grava relatorio, compactado, hash nem arquivo de
log. Use `--report-only` para gerar relatorio mensal sem compactar.

Compactacao real mantendo originais:

```bash
arquivar-antigos-siha.sh --year 2024 --format zip --verbose
```

Remocao de originais so e permitida com flag explicita e depois de verificacao:

```bash
arquivar-antigos-siha.sh --year 2024 --format zip --remove-originals-after-verify
```

## Restaurar arquivo compactado

Para `.zip`, use Explorer no Windows ou:

```bash
unzip -l /dados/siha/91_ARQUIVO_COMPACTADO/2024/SIHA_ARQUIVO_2024_REMESSAS_E_RETORNOS.zip
unzip /dados/siha/91_ARQUIVO_COMPACTADO/2024/SIHA_ARQUIVO_2024_REMESSAS_E_RETORNOS.zip -d /tmp/siha-restauracao
```

Confira o hash:

```bash
sha256sum -c /dados/siha/99_MANIFESTOS_HASHES/SIHA_ARQUIVO_2024_REMESSAS_E_RETORNOS.zip.sha256
```

## Logs

- Provisionamento: `/var/log/siha-nas/provision-*.log`
- Indice: `/var/log/siha-nas/gerar-indice-*.log`
- Arquivamento: `/var/log/siha-nas/arquivar-antigos-*.log`
- Samba: `/var/log/samba/`

## Backup

O share Samba nao e backup. Ele e armazenamento operacional. Mantenha snapshot
e backup externo nao gravavel pela VM Windows. Veja
`docs/siha-nas/BACKUP_E_RESTAURACAO.md`.

## Risco de ransomware

Tudo que a VM Windows consegue escrever tambem pode ser apagado ou criptografado
por malware rodando nela. Por isso, snapshots e backups precisam estar fora do
alcance de escrita da VM.
