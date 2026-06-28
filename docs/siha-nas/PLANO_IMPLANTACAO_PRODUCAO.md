# Plano de implantacao em producao do siha-nas

Este documento prepara a implantacao real do `siha-nas` apos o teste controlado bem-sucedido em CT descartavel. Ele nao altera a arquitetura: LXC Debian unprivileged, Samba dentro do container, dados em `/dados/siha`, acesso Windows por `\\siha-nas\SIHA` e unidade `S:`.

Nao execute a implantacao real sem preencher os campos abaixo, confirmar backup/restauracao e validar que o CT definitivo nao conflita com outro servico.

## Campos da implantacao

| Campo | Valor aprovado |
|---|---|
| CTID definitivo | `7010` |
| Hostname | `siha-nas` |
| IP | `192.168.1.163/24` |
| Gateway | `192.168.1.1` |
| DNS | `siha-nas` resolve para `192.168.1.163` na VM SIHA |
| Storage rootfs | `rpool` |
| Tamanho rootfs | `64` GB |
| Storage dados | `rpool`, dados dentro do rootfs em `/dados/siha` |
| Tipo de mount point | sem bind mount; dados dentro do rootfs gerenciado pelo Proxmox |
| Politica de backup | semanal rotativo de 4 semanas; `vzdump` do CT inclui `/dados/siha`; manter copia externa nao gravavel pela VM quando disponivel |
| Usuario Samba inicial | `siha_user` |
| VM cliente | `7001 SIHA`, `Administrator@192.168.1.97` |
| Unidade Windows | `S:` |
| Template Debian | `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst` |
| Rede permitida SMB | `192.168.1.0/24` |
| Infisical path | Projeto de templates, `/siha-nas`, chaves com prefixo `SIHA_NAS_*` |

## Decisoes obrigatorias antes de produzir

- Confirmar IP fixo ou reserva DHCP/DNS para `siha-nas`; o teste controlado mostrou que nome e IP precisam estar alinhados antes do aceite Windows.
- Confirmar se `/dados/siha` ficara dentro do rootfs gerenciado pelo Proxmox ou em mount point dedicado.
- Se houver bind mount/dataset do host, documentar UID/GID mapping do LXC unprivileged antes de gravar dados reais. Nao assumir que UID `1000` dentro do CT equivale a UID `1000` no host.
- Confirmar que o backup cobre os dados. Se os dados estiverem em bind mount, o backup do CT pode nao incluir os arquivos.
- Confirmar que a VM Windows nao e a unica copia dos dados e que ha backup nao gravavel pela VM.
- Confirmar que o CT descartavel `7010` sera removido ou isolado antes da implantacao definitiva para evitar conflito de hostname/IP.
- Confirmar que `EnableLinkedConnections=1` esta aplicado na VM Windows se a unidade `S:` existir mas nao aparecer no Explorer do operador.

## Checklist pre-producao

- [ ] Todos os campos da implantacao foram preenchidos.
- [ ] `git status` revisado e sem alteracoes inesperadas.
- [ ] Commit/tag da versao a implantar registrado.
- [ ] CTID definitivo livre no Proxmox.
- [ ] IP definitivo livre e reservado no DNS/DHCP.
- [ ] Template Debian confirmado no Proxmox.
- [ ] Storage rootfs com espaco suficiente.
- [ ] Storage dados definido e com espaco suficiente.
- [ ] Politica de backup aprovada.
- [ ] Politica semanal rotativa de 4 semanas configurada ou agendada.
- [ ] Variaveis SIHA NAS sincronizadas no Infisical em `/siha-nas`.
- [ ] Procedimento de restore testado em CT descartavel antes de dados reais.
- [ ] Senha Samba definida por canal seguro, sem registrar em comando, chat, log ou documento.
- [ ] VM SIHA acessivel e usuario operacional confirmado.
- [ ] Porta SMB `445/tcp` restrita a rede interna necessaria.
- [ ] Samba nao sera instalado no host Proxmox.
- [ ] Container permanecera `unprivileged: 1`.

## Verificar versao do repositorio

Execute no checkout local antes de qualquer acao real:

```powershell
rtk git status --short
rtk git rev-parse --abbrev-ref HEAD
rtk git rev-parse HEAD
rtk git tag --points-at HEAD
```

Se nao houver tag para a versao implantada, criar uma tag somente depois de revisar o diff e confirmar que este e o estado desejado:

```powershell
rtk git diff --check
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-SihaNas.ps1
rtk git tag -a siha-nas-prod-AAAA-MM-DD -m "SIHA NAS production deployment baseline"
```

## Sincronizar variaveis Infisical

As chaves operacionais do `siha-nas` ficam no projeto Infisical de templates,
em `/siha-nas`, usando o prefixo `SIHA_NAS_*`. Esse path e o escopo permitido
para este conjunto no projeto de templates. O script deve
resolver a conexao por `TEMPLATE_INFISICAL_*`, aceitando
`TEMPLATES_INFISICAL_*` como alias local de compatibilidade. Nao usar
`INFISICAL_*`, pois esse namespace aponta para o projeto ESUS PEC. O arquivo
`config/siha-nas.infisical.env.example` deve conter apenas nomes e valores nao
sensiveis. A senha Samba deve ser sincronizada a partir de `.env` ou
`../sus-siha-bootstrap/.env`, sem ser impressa.

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1 -DryRun
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1
```

O relatorio esperado mostra `path`, `action`, `valuePresent` e `sensitive`, mas
nunca mostra valores.

## Preflight no Proxmox

Substitua os placeholders antes de executar:

```powershell
$CTID = "PREENCHER"
$TEMPLATE = "PREENCHER"
$IPCONFIG = "PREENCHER,gw=PREENCHER"
$STORAGE = "PREENCHER"
$ROOTFS_GB = "PREENCHER"
```

Comandos de leitura para confirmar o ambiente:

```powershell
rtk ssh root@192.168.1.149 "pct status $CTID"
rtk ssh root@192.168.1.149 "pveam list local"
rtk ssh root@192.168.1.149 "pvesm status"
rtk ssh root@192.168.1.149 "ip neigh show"
```

O comando `pct status $CTID` deve falhar com configuracao inexistente para indicar que o CTID esta livre. Se existir, parar e revisar.

## Provisionamento real

Primeiro rode dry-run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/siha-nas/Provision-SihaNas.ps1 `
  -TargetCtid $CTID `
  -TargetName "siha-nas" `
  -DebianTemplate $TEMPLATE `
  -StoragePool $STORAGE `
  -RootFsSizeGb $ROOTFS_GB `
  -IpConfig $IPCONFIG `
  -AllowedCidr "PREENCHER" `
  -CreateContainer `
  -StartContainer `
  -DryRun
```

Se o dry-run estiver correto, executar provisionamento real e definir a senha inicial Samba por prompt seguro:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/siha-nas/Provision-SihaNas.ps1 `
  -TargetCtid $CTID `
  -TargetName "siha-nas" `
  -DebianTemplate $TEMPLATE `
  -StoragePool $STORAGE `
  -RootFsSizeGb $ROOTFS_GB `
  -IpConfig $IPCONFIG `
  -AllowedCidr "PREENCHER" `
  -CreateContainer `
  -StartContainer `
  -SetInitialSambaPassword
```

Nao passar senha Samba por argumento de linha de comando.

## Validacao do CT

Validar configuracao do container:

```powershell
rtk ssh root@192.168.1.149 "pct config $CTID"
rtk ssh root@192.168.1.149 "pct config $CTID | grep -E '^hostname:|^unprivileged:|^net0:|^rootfs:'"
rtk ssh root@192.168.1.149 "pct config $CTID | grep -q '^unprivileged: 1$' && echo unprivileged_ok"
rtk ssh root@192.168.1.149 "pct exec $CTID -- hostname -I"
```

Validar Samba:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- testparm -s"
rtk ssh root@192.168.1.149 "pct exec $CTID -- systemctl status smbd --no-pager"
rtk ssh root@192.168.1.149 "pct exec $CTID -- systemctl is-active smbd"
```

Validar usuario Samba:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- pdbedit -L"
```

Testar `smbclient` sem expor senha. Criar um arquivo de credenciais temporario dentro do CT com permissao `0600`, executar o teste e remover o arquivo:

```bash
pct exec <CTID> -- bash -lc 'umask 077; cat > /run/siha-smbclient-creds'
```

Conteudo digitado manualmente no prompt do terminal seguro:

```text
username = siha_user
password = <NAO_REGISTRAR>
```

Teste:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- smbclient //127.0.0.1/SIHA -A /run/siha-smbclient-creds -c 'ls'"
rtk ssh root@192.168.1.149 "pct exec $CTID -- rm -f /run/siha-smbclient-creds"
```

## Mapeamento da unidade S: na VM Windows

Na sessao interativa do usuario operacional da VM SIHA, salvar a credencial no Windows Credential Manager sem registrar senha em script:

```powershell
cmdkey /add:siha-nas /user:siha_user /pass
```

Executar o script oficial na VM Windows:

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\caminho\para\mapear-siha-nas.ps1 -NasHost siha-nas -Share SIHA -DriveLetter S -Force
```

Validar na VM:

```powershell
Test-NetConnection siha-nas -Port 445
Get-SmbMapping -LocalPath S:
Test-Path S:\
New-Item -ItemType Directory -Path S:\98_RELATORIOS_DE_AUDITORIA\TESTE_ACEITE_PRODUCAO -Force
"teste-siha-nas-producao" | Set-Content S:\98_RELATORIOS_DE_AUDITORIA\TESTE_ACEITE_PRODUCAO\teste.txt -Encoding UTF8
Get-Content S:\98_RELATORIOS_DE_AUDITORIA\TESTE_ACEITE_PRODUCAO\teste.txt
Remove-Item S:\98_RELATORIOS_DE_AUDITORIA\TESTE_ACEITE_PRODUCAO\teste.txt -Force
Remove-Item S:\98_RELATORIOS_DE_AUDITORIA\TESTE_ACEITE_PRODUCAO -Force
```

Validar no CT que a lixeira Samba recebeu o arquivo removido:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- find /dados/siha/.lixeira -maxdepth 8 -type f -iname '*teste.txt' -print"
```

## Indice e arquivamento inicial

Gerar indice do ano atual:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- /usr/local/sbin/gerar-indice-siha.sh --ano 2026 --base /dados/siha --output /dados/siha/99_MANIFESTOS_HASHES/indice_2026.csv"
```

Executar arquivamento em modo relatorio, sem compactar:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- /usr/local/sbin/arquivar-antigos-siha.sh --base /dados/siha --older-than-days 730 --report-only --verbose"
```

Nao executar compactacao real nem remocao de originais na primeira janela de producao, salvo se houver aprovacao operacional especifica.

## Teste obrigatorio de backup e restauracao antes de dados reais

Este teste deve acontecer antes de usuarios copiarem dados reais para `S:`.

1. Criar arquivo sintetico no share pela VM Windows.
2. Gerar indice.
3. Executar backup `vzdump` do CT definitivo.
4. Restaurar em CTID descartavel livre.
5. Validar que `/dados/siha`, indices, relatorios e arquivo sintetico foram restaurados.
6. Remover o CT restaurado descartavel.
7. Registrar caminho do backup e resultado.

Comandos modelo:

```powershell
$RESTORE_CTID = "PREENCHER_CTID_DESCARTAVEL"
rtk ssh root@192.168.1.149 "vzdump $CTID --mode snapshot --storage local --compress zstd --notes-template 'siha-nas production pre-data restore test'"
rtk ssh root@192.168.1.149 "ls -1t /var/lib/vz/dump/vzdump-lxc-$CTID-*.tar.zst | head -n 1"
```

Restaurar usando o arquivo retornado:

```powershell
$BACKUP_FILE = "PREENCHER_CAMINHO_BACKUP"
rtk ssh root@192.168.1.149 "pct restore $RESTORE_CTID $BACKUP_FILE --storage $STORAGE --unique 1"
rtk ssh root@192.168.1.149 "pct start $RESTORE_CTID"
rtk ssh root@192.168.1.149 "pct exec $RESTORE_CTID -- test -d /dados/siha"
rtk ssh root@192.168.1.149 "pct exec $RESTORE_CTID -- find /dados/siha -maxdepth 3 -type f | head"
rtk ssh root@192.168.1.149 "pct stop $RESTORE_CTID && pct destroy $RESTORE_CTID --purge 1"
```

Se o armazenamento de dados for bind mount, repetir o teste com o metodo de backup especifico desse storage, porque `vzdump` pode nao incluir os dados.

## Checklist de execucao

- [ ] Dry-run revisado.
- [ ] Provisionamento real concluiu sem erro.
- [ ] `pct config` mostra hostname correto.
- [ ] `pct config` mostra `unprivileged: 1`.
- [ ] IP e DNS de `siha-nas` resolvem corretamente na VM SIHA.
- [ ] `testparm -s` sem erro.
- [ ] `smbd` ativo.
- [ ] `pdbedit -L` lista `siha_user`.
- [ ] `smbclient` autenticado lista o share.
- [ ] Unidade `S:` mapeada na sessao interativa do usuario operacional.
- [ ] Arquivo criado pela VM foi lido no CT.
- [ ] Arquivo removido pela VM apareceu na lixeira Samba.
- [ ] Indice anual gerado.
- [ ] Arquivamento `--report-only` gerou relatorio.
- [ ] Backup e restore em CT descartavel passaram antes de dados reais.

## Rollback

### Parar CT

```powershell
rtk ssh root@192.168.1.149 "pct stop $CTID"
```

Se precisar impedir acesso SMB sem destruir dados:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- systemctl stop smbd nmbd"
```

### Desmapear unidade Windows

Na VM SIHA, sessao do usuario operacional:

```powershell
Remove-SmbMapping -LocalPath S: -Force
cmdkey /delete:siha-nas
```

Fallback:

```powershell
net use S: /delete /y
cmdkey /delete:siha-nas
```

### Preservar dados

- Nao executar `pct destroy` se houver qualquer dado real em `/dados/siha`.
- Antes de remover CT, gerar backup e validar restore.
- Se os dados estiverem em mount point dedicado, documentar o caminho e preservar o volume/dataset.
- Copiar relatorios de auditoria e manifestos para local seguro se o CT for descartado.

### Remover CT apenas se vazio ou apos backup validado

Confirmar conteudo:

```powershell
rtk ssh root@192.168.1.149 "pct exec $CTID -- find /dados/siha -mindepth 2 -type f | head -n 50"
```

Se estiver vazio ou se houver backup validado e aprovacao explicita:

```powershell
rtk ssh root@192.168.1.149 "pct stop $CTID"
rtk ssh root@192.168.1.149 "pct destroy $CTID --purge 1"
```

Nao destruir o CT se o backup nao foi restaurado e validado.

## Aceite final

O aceite final so pode ser registrado quando todos os itens abaixo estiverem concluídos:

- [ ] CT definitivo criado com CTID, hostname, IP e storage aprovados.
- [ ] CT permanece `unprivileged: 1`.
- [ ] Samba validado com `testparm`.
- [ ] `smbd` ativo apos reboot do CT.
- [ ] `siha_user` autenticou no share `[SIHA]`.
- [ ] VM SIHA resolveu `siha-nas` para o IP definitivo.
- [ ] Unidade `S:` aparece no Explorer para o usuario operacional.
- [ ] Arquivo de teste criado pela VM foi lido no CT.
- [ ] Remocao pela VM foi preservada na lixeira Samba.
- [ ] Indice anual gerado com SHA256.
- [ ] Arquivamento `--report-only` executado.
- [ ] Backup antes de dados reais foi restaurado em CT descartavel e validado.
- [ ] Politica de backup recorrente foi documentada e agendada fora da VM Windows.
- [ ] Risco de ransomware por unidade gravavel foi comunicado aos operadores.
- [ ] CT descartavel do teste controlado foi removido ou isolado para nao conflitar com producao.
