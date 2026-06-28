# Troubleshooting SIHA NAS

## Windows nao abre `\\siha-nas\SIHA`

No Windows:

```powershell
Test-NetConnection siha-nas -Port 445
```

Se falhar, verifique DNS, IP do container, firewall Proxmox e firewall interno
do LXC.

## Credencial recusada

No container:

```bash
pdbedit -L
smbpasswd -e siha_user
getent group siha_faturamento
```

Redefina a senha:

```bash
smbpasswd siha_user
```

## `testparm` falha

```bash
testparm -s /etc/samba/smb.conf
journalctl -u smbd -n 100 --no-pager
```

Restaure `/etc/samba/smb.conf.siha-nas-original` somente se precisar voltar ao
estado anterior. Antes, salve a configuracao atual para auditoria.

## Permissao negada ao criar arquivo

Verifique:

```bash
namei -l /dados/siha
find /dados/siha -maxdepth 2 -type d -printf '%m %u %g %p\n'
```

Esperado: diretorios `2770`, grupo `siha_faturamento`.

## Indice nao gera hash

```bash
command -v sha256sum
gerar-indice-siha.sh --dry-run --ano 2026 --verbose
```

Arquivos temporarios, locks, cache e lixeira sao ignorados.

## Planilha interpreta campo como formula

Os scripts mitigam CSV injection prefixando campos iniciados por `=`, `+`, `-`,
`@` ou tab. Se alguem criou um arquivo antigo com nome como `=formula.csv`,
renomeie para o padrao operacional antes de usar o CSV em planilhas.

## Arquivamento acusa espaco insuficiente

O script exige espaco para manter original e compactado ao mesmo tempo. Libere
espaco ou aumente o volume antes de compactar.

## Bind mount em LXC unprivileged

Leia os mapas reais:

```bash
pct config CTID
pct exec CTID -- cat /proc/self/uid_map
pct exec CTID -- cat /proc/self/gid_map
```

Corrija ownership no host conforme o deslocamento real de UID/GID.
