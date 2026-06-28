# Checklist de testes SIHA NAS

## Container

- [ ] CT existe com hostname `siha-nas`.
- [ ] `pct config CTID` mostra `unprivileged: 1`.
- [ ] Container esta rodando Debian stable.
- [ ] Samba nao foi instalado no host Proxmox.
- [ ] `smbd` esta ativo dentro do container.

## Samba

- [ ] `testparm -s /etc/samba/smb.conf` nao retorna erro.
- [ ] `server min protocol = SMB2_10` ou superior.
- [ ] Guest/anonymo desabilitado.
- [ ] Usuario `siha_user` existe no Samba.
- [ ] Grupo `siha_faturamento` existe.
- [ ] `smbclient -L //127.0.0.1 -U siha_user` lista `SIHA`.
- [ ] `smbclient //127.0.0.1/SIHA -U siha_user -c 'ls'` funciona.

## Windows

- [ ] `Test-NetConnection siha-nas -Port 445` retorna sucesso.
- [ ] `\\siha-nas\SIHA` abre no Explorer.
- [ ] Unidade `S:` mapeada.
- [ ] Arquivo criado pela VM aparece em `/dados/siha`.
- [ ] Permissao de arquivo criada como grupo `siha_faturamento` e modo 0660.
- [ ] Diretorios usam modo 2770.
- [ ] Exclusao pelo Windows vai para `.lixeira/%U`.

## Estrutura e legibilidade

- [ ] Todas as pastas obrigatorias existem.
- [ ] Cada pasta tem `.README.txt`.
- [ ] `00_LEIA-ME/CONVENCAO_DE_NOMES.md` existe.
- [ ] Nome de arquivo segue o padrao recomendado.
- [ ] Indice anual foi gerado.
- [ ] Hash SHA256 aparece no indice.

## Arquivamento

- [ ] `arquivar-antigos-siha.sh --dry-run` funciona.
- [ ] `arquivar-antigos-siha.sh --report-only` gera Markdown e CSV.
- [ ] Compactacao teste cria arquivo em `91_ARQUIVO_COMPACTADO/AAAA/`.
- [ ] Arquivo compactado passa em `unzip -t` ou `tar -tf`.
- [ ] Hash do compactado foi registrado.
- [ ] Originais nao sao removidos sem `--remove-originals-after-verify`.
- [ ] Restauracao de arquivo compactado foi testada e documentada.

## Backup

- [ ] `pct config CTID` confirma se os dados entram no backup do container.
- [ ] Se houver bind mount, UID/GID mapping foi documentado.
- [ ] Existe backup externo nao gravavel pela VM Windows.
- [ ] Restauracao de arquivo unico foi testada.
- [ ] Retencao diaria/semanal/mensal foi configurada ou registrada como pendencia.
