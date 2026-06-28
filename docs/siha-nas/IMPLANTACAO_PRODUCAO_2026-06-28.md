---
data: 2026-06-28
ambiente: Proxmox 192.168.1.149
ctid: 7010
hostname: siha-nas
status: aceite-tecnico-concluido
---

# Implantacao em producao do siha-nas

## Escopo executado

Implantacao real do `siha-nas` usando o mesmo CTID do teste controlado, conforme aprovacao operacional.

O CT descartavel `7010` foi parado e destruido. Em seguida, o CT definitivo foi criado com a mesma identidade operacional:

```text
CTID: 7010
hostname: siha-nas
IP: 192.168.1.163/24
gateway: 192.168.1.1
storage rootfs: rpool
storage dados: rpool, dentro do rootfs em /dados/siha
rootfs: 64G
template: local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
rede SMB permitida: 192.168.1.0/24
VM cliente: 7001 SIHA
unidade Windows: S:
usuario Samba inicial: siha_user
politica de backup: semanal rotativo de 4 semanas
```

## Comando de provisionamento usado

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/siha-nas/Provision-SihaNas.ps1 `
  -TargetCtid 7010 `
  -TargetName siha-nas `
  -DebianTemplate "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" `
  -StoragePool rpool `
  -RootFsSizeGb 64 `
  -IpConfig "192.168.1.163/24,gw=192.168.1.1" `
  -AllowedCidr "192.168.1.0/24" `
  -CreateContainer `
  -StartContainer
```

A senha Samba de `siha_user` foi aplicada por arquivo temporario restrito a partir do ambiente local seguro. O valor da senha nao foi registrado neste relatorio.

## Validacoes do CT

Resultado validado:

- `pct config 7010` mostra `hostname: siha-nas`.
- `pct config 7010` mostra `unprivileged: 1`.
- `rootfs: rpool:subvol-7010-disk-0,size=64G`.
- `net0` usa `ip=192.168.1.163/24` e `gw=192.168.1.1`.
- `testparm -s` carregou a configuracao Samba sem erro.
- `smbd` ficou `active`.
- `pdbedit -L` listou `siha_user`.
- `smbclient //127.0.0.1/SIHA` autenticado passou.
- Diretorios em `/dados/siha` foram criados com permissao `2770` e grupo `siha_faturamento`.

## Validacao Windows

Na VM `7001 SIHA`, o script `scripts/windows/mapear-siha-nas.ps1` foi executado na sessao interativa do usuario `SIHA-DESKTOP\Administrator`, sessao `1`, usando PsExec local da propria VM.

Resultado:

```json
{
  "user": "SIHA-DESKTOP\\Administrator",
  "session_id": 1,
  "connectivity": true,
  "cmdkey_added": true,
  "script_executed": true,
  "net_use_executed": true,
  "drive_exists": true,
  "remote_path": "\\\\siha-nas\\SIHA",
  "registry_remote_path": "\\\\siha-nas\\SIHA",
  "created": true,
  "read_back": true,
  "removed": true,
  "error": null
}
```

A unidade `S:` ficou persistente no perfil do Administrator e aponta para:

```text
\\siha-nas\SIHA
```

Em verificacao posterior, o operador informou que `S:` nao apareceu no Explorer.
Foi aplicada a chave do Windows abaixo para compartilhar mapeamentos entre o
token elevado e o Explorer do mesmo usuario:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
EnableLinkedConnections = 1
```

O valor foi confirmado como `REG_DWORD 0x1`. A aplicacao visual no Explorer pode
exigir logoff/login do Administrator ou reinicio do Explorer.

Depois do reinicio da VM SIHA, o operador confirmou que a unidade `S:` apareceu
no Explorer.

O arquivo removido pela VM apareceu na lixeira Samba:

```text
/dados/siha/.lixeira/siha_user/98_RELATORIOS_DE_AUDITORIA/TESTE_ACEITE_PRODUCAO/teste.txt
```

## Indice e arquivamento inicial

Indice inicial gerado:

```text
/dados/siha/99_MANIFESTOS_HASHES/indice_2026.csv
```

Resultado:

```text
Indice gravado em /dados/siha/99_MANIFESTOS_HASHES/indice_2026.csv com 11 arquivo(s).
```

Arquivamento inicial em `--report-only`:

```text
Candidatos encontrados: 0
Nenhum arquivo compactado neste modo.
```

Relatorio gerado em:

```text
/dados/siha/98_RELATORIOS_DE_AUDITORIA/arquivamento_todos_20260628T174126.md
```

## Registro no Infisical

As variaveis operacionais do `siha-nas` devem ficar em:

```text
/siha-nas
```

As variaveis devem ser gravadas no projeto Infisical de templates, nao no
projeto ESUS PEC. O script usa `TEMPLATE_INFISICAL_*` como namespace de
configuracao e aceita `TEMPLATES_INFISICAL_*` como alias local de
compatibilidade. Nao usar `INFISICAL_*` para esta rotina. As chaves usam o
prefixo `SIHA_NAS_*` para nao se misturarem com as chaves MinIO/WAL-G. O
arquivo rastreado `config/esus-pec.infisical.env.example` lista as chaves sem
valores sensiveis. A sincronizacao deve ser feita pelo script:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1 -DryRun
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1
```

O relatorio do script mostra apenas path, acao e presenca de valor. A senha
Samba fica em `SIHA_NAS_SAMBA_PASSWORD` no Infisical e pode ser lida localmente
de `SIHA_NAS_SAMBA_PASSWORD` ou `siha_password`, sem imprimir o valor.

Se as chaves forem criadas por engano no projeto ESUS PEC, remover usando o
prefixo explicito antigo e o path antigo `/test/ObjectStorage`; depois
sincronizar no projeto de templates em `/siha-nas`:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1 -InfisicalSettingPrefix INFISICAL -InfisicalSecretPath /test/ObjectStorage -RemoveOnly -DryRun
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1 -InfisicalSettingPrefix INFISICAL -InfisicalSecretPath /test/ObjectStorage -RemoveOnly
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1 -DryRun
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1
```

## Backup e restore antes de dados reais

Backup pre-dados reais:

```text
/var/lib/vz/dump/vzdump-lxc-7010-2026_06_28-14_41_56.tar.zst
```

Resultado:

- `vzdump` concluiu com sucesso.
- Restore executado em CT descartavel `7011` no `rpool`.
- CT restaurado iniciou corretamente.
- Foram validados:
  - `/dados/siha`;
  - `/dados/siha/99_MANIFESTOS_HASHES/indice_2026.csv`;
  - relatorio `arquivamento_todos_20260628T174126.md`;
  - arquivo removido preservado na lixeira Samba;
  - `gerar-indice-siha.sh --dry-run --ano 2026`.
- CT descartavel `7011` foi removido apos a validacao.

## Avisos operacionais

- O template Debian 13 emitiu avisos de locale `en_US.UTF-8` durante instalacao de pacotes. Nao bloqueou o provisionamento.
- O storage de dados esta dentro do rootfs do CT em `rpool`; portanto o `vzdump` do CT inclui `/dados/siha`.
- O compartilhamento SMB nao substitui backup. Politica aprovada: backup semanal rotativo de 4 semanas, preferencialmente com copia externa nao gravavel pela VM Windows quando disponivel.
- A unidade `S:` e gravavel pela VM Windows; manter protecao contra ransomware por backup/snapshot nao acessivel pela VM.

## Aceite tecnico

- [x] CT definitivo criado com CTID `7010`.
- [x] CT permanece `unprivileged: 1`.
- [x] Samba validado com `testparm`.
- [x] `smbd` ativo.
- [x] `siha_user` autenticou no share `[SIHA]`.
- [x] VM SIHA acessa `\\siha-nas\SIHA`.
- [x] Unidade `S:` persistente no perfil do Administrator.
- [x] Arquivo de teste criado pela VM foi lido e removido.
- [x] Remocao pela VM foi preservada na lixeira Samba.
- [x] Indice anual gerado.
- [x] Arquivamento `--report-only` executado.
- [x] Backup pre-dados reais restaurado em CT descartavel e validado.

Aceite tecnico concluido. Antes de uso operacional, confirmar visualmente no Explorer da VM SIHA que a unidade `S:` aparece para o operador e registrar a politica de backup recorrente no calendario de operacao.
