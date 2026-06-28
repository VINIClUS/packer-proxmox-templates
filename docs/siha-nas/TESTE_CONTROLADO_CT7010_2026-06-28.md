---
data: 2026-06-28
ambiente: Proxmox 192.168.1.149
ct_teste: 7010
status: validacao-parcial
---

# Teste controlado do siha-nas em CT descartavel

## Escopo

Teste executado em container descartavel `7010`, hostname `siha-nas`, para validar o provisionamento e os scripts operacionais antes de qualquer implantacao definitiva.

O template Debian 12 solicitado inicialmente nao estava disponivel no storage `local`. O download iniciado para `debian-12-standard_12.12-1_amd64.tar.zst` foi interrompido, o artefato parcial foi removido, e o teste prosseguiu com o template ja disponivel no Proxmox:

```text
local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
```

## Comandos principais executados

Provisionamento:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/siha-nas/Provision-SihaNas.ps1 `
  -TargetCtid 7010 `
  -DebianTemplate "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" `
  -CreateContainer `
  -StartContainer
```

Validacoes no CT:

```bash
testparm -s
systemctl status smbd --no-pager
/usr/local/sbin/gerar-indice-siha.sh --dry-run --ano 2026
/usr/local/sbin/arquivar-antigos-siha.sh --report-only --older-than-days 730
```

Observacao: via `pct exec`, o `PATH` recebido foi `/sbin:/bin:/usr/sbin:/usr/bin`, por isso os scripts administrativos instalados em `/usr/local/sbin` foram executados por caminho absoluto. Em uma sessao root normal dentro do CT, validar o `PATH` antes de usar o nome curto.

## Resultado validado

- CT `7010` criado como LXC unprivileged.
- Configuracao confirmou `unprivileged: 1`.
- IP do CT no teste: `192.168.1.166`.
- Samba instalado dentro do CT, nao no host Proxmox.
- `testparm -s` carregou a configuracao sem erro.
- `smbd.service` ficou `active (running)`.
- SMB1 desabilitado via `server min protocol = SMB2` e `client min protocol = SMB2`.
- Guest/anonimo nao habilitado.
- Share `[SIHA]` protegido por `valid users = @siha_faturamento`.
- Permissoes de diretorio principais em `2770` com grupo `siha_faturamento`.
- Indice real `indice_2026.csv` gerado.
- `arquivar-antigos-siha.sh --report-only` gerou relatorio sem compactar.

## Teste de arquivamento e restauracao de arquivo

Foi criado um arquivo sintetico antigo em:

```text
/dados/siha/01_REMESSAS_MS/2023/2023-01-15_SIHA_2022-12_REMESSA_MS_TESTE-CONTROLADO.txt
```

Hash original:

```text
5f38edd5ffd6b04b9ecc91694ca49a7690f9d403712960ba2d33da18992d4c6b
```

Resultados:

- `arquivar-antigos-siha.sh --dry-run --older-than-days 730 --year 2023 --format zip` encontrou 1 candidato.
- `gerar-indice-siha.sh --ano 2023` gerou `indice_2023.csv`.
- Compactacao real sem remover originais criou:

```text
/dados/siha/91_ARQUIVO_COMPACTADO/2023/SIHA_ARQUIVO_2023_REMESSAS_E_RETORNOS.zip
```

- `unzip -t` retornou sem erros.
- O arquivo original de teste foi removido manualmente.
- A restauracao para `/tmp/siha-nas-restore-test` preservou o hash original.
- Temporarios fora da arvore de dados foram removidos.

## Teste de backup e restore Proxmox

Foi executado backup `vzdump` do CT `7010`:

```text
/var/lib/vz/dump/vzdump-lxc-7010-2026_06_28-11_06_34.tar.zst
```

Resultado:

- Backup finalizado com sucesso.
- Restore testado no CT descartavel `7011`.
- No CT restaurado, foram validados:
  - `/dados/siha`;
  - `indice_2023.csv`;
  - ZIP compactado de 2023;
  - `unzip -t` do ZIP restaurado.
- CT `7011` foi removido apos a validacao.

O backup foi mantido no host como evidencia do teste. Remover manualmente quando nao for mais necessario.

## Teste pela VM Windows SIHA

A VM `7001 SIHA` estava ligada e o QEMU Guest Agent respondeu.

Na primeira etapa, o CT recebeu `192.168.1.166` por DHCP, mas a VM resolvia `siha-nas.intelbras.local` para `192.168.1.163`. Como `192.168.1.163` nao respondeu a ping e apareceu como `INCOMPLETE` na tabela de vizinhanca do Proxmox, o CT descartavel foi ajustado para IP estatico `192.168.1.163/24`, gateway `192.168.1.1`, apenas para alinhar o teste ao nome ja resolvido pela VM.

Apos o ajuste, dentro da VM, `Test-NetConnection siha-nas -Port 445` resolveu `siha-nas` para `192.168.1.163` e a porta 445 respondeu.

A senha Samba de teste foi aplicada para `siha_user` por arquivo temporario restrito, sem registrar o valor em linha de comando ou relatorio. O teste autenticado local com `smbclient` no CT criou, listou e removeu arquivo no share `[SIHA]`.

Como o QEMU Guest Agent executa comandos fora da sessao interativa do usuario, `New-SmbMapping` retornou `Windows System Error 1312` quando usado diretamente. Para validar escrita/leitura pela VM, foi copiado temporariamente um script para `C:\Windows\Temp` e executado via QEMU Guest Agent usando `net use S: \\siha-nas\SIHA /persistent:no`. Resultado validado:

- mapeamento temporario `S:` na sessao do processo de teste;
- criacao de arquivo em `\\siha-nas\SIHA`;
- leitura do mesmo arquivo pela VM;
- remocao do arquivo pela VM;
- desmontagem da unidade temporaria;
- remocao do script temporario em `C:\Windows\Temp`.

A lixeira Samba registrou o arquivo removido pela VM em:

```text
/dados/siha/.lixeira/siha_user/98_RELATORIOS_DE_AUDITORIA/TESTE_WINDOWS_SIHA/teste_ct7010_windows.txt
```

Depois do teste Windows, `gerar-indice-siha.sh --ano 2026` gerou `indice_2026.csv` com 17 arquivos.

### Validacao interativa da unidade S:

Em seguida, `scripts/windows/mapear-siha-nas.ps1` foi copiado temporariamente para a VM e executado na sessao console ativa do usuario operacional `SIHA-DESKTOP\Administrator`, sessao `1`, usando PsExec local da propria VM (`C:\sus-automation\tools\PsExec64.exe`) com `-i 1 -h`.

A credencial Samba foi carregada a partir de arquivo temporario restrito e removida ao final. O valor da senha nao foi registrado no relatorio.

Resultado da execucao interativa:

```json
{
  "user": "SIHA-DESKTOP\\Administrator",
  "session_id": 1,
  "connectivity": true,
  "cmdkey_added": true,
  "script_executed": true,
  "drive_exists": true,
  "remote_path": "\\\\siha-nas\\SIHA",
  "created": true,
  "read_back": true,
  "removed": true,
  "error": null
}
```

Observacao operacional: apos a execucao do script oficial, a validacao materializou a unidade com `net use S: \\siha-nas\SIHA /persistent:yes` usando a credencial ja salva no Windows Credential Manager. Isso foi necessario porque a criacao por `New-SmbMapping` ocorreu em um child PowerShell e a unidade nao ficou imediatamente visivel no processo validador, embora o mapeamento SMB estivesse registrado. A unidade `S:` ficou persistente para a sessao do Administrator.

O arquivo de teste criado/removido via `S:` foi enviado para a lixeira Samba:

```text
/dados/siha/.lixeira/siha_user/98_RELATORIOS_DE_AUDITORIA/TESTE_WINDOWS_SIHA_INTERATIVO/teste_mapeamento_interativo.txt
```

Tambem foi validado no registro do perfil do Administrator que o mapeamento persistente foi gravado em `HKU\<SID>\Network\S` com:

```json
{
  "RemotePath": "\\\\siha-nas\\SIHA",
  "ProviderName": "Microsoft Windows Network"
}
```

Os artefatos temporarios em `C:\Windows\Temp\siha-nas-map-test` foram removidos ao final. Depois da validacao interativa, `gerar-indice-siha.sh --ano 2026` gerou `indice_2026.csv` com 17 arquivos.

## Pendencias antes de aceite real

- Definir credencial Samba para `siha_user` sem expor senha em chat, logs ou linha de comando.
- Confirmar visualmente no Explorer da VM Windows SIHA que a unidade `S:` aparece para o usuario operacional correto apos refresh/reabertura do Explorer.
- Definir se o CT definitivo usara Debian 12 baixado previamente ou Debian disponivel no Proxmox.
- Remover o CT descartavel `7010` quando o operador encerrar a validacao.

## Avisos observados

- O template Debian 13 emitiu avisos de locale (`en_US.UTF-8` nao gerado). O provisionamento concluiu, mas vale corrigir locale no template/provisionamento se o ruido for indesejado.
- O `vzdump` alertou que o thin pool nao tem autoextend/protecao contra esgotamento habilitada. Isso nao bloqueou o teste, mas deve ser tratado como risco operacional de storage.
- Este teste valida o CT descartavel. Nao declarar pronto para producao ate concluir o acesso SMB real pela VM Windows e o procedimento operacional de senha/backup definitivo.
