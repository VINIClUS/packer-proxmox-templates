# Rollback SIHA NAS

## Reverter configuracao Samba

O provisionamento salva o arquivo original em:

```text
/etc/samba/smb.conf.siha-nas-original
```

Para restaurar:

```bash
cp -a /etc/samba/smb.conf.siha-nas-original /etc/samba/smb.conf
testparm -s /etc/samba/smb.conf
systemctl restart smbd
```

## Desabilitar timer

```bash
systemctl disable --now siha-arquivar-antigos.timer
```

## Desabilitar firewall interno opcional

```bash
systemctl disable --now siha-nas-firewall.service
nft delete table inet siha_nas_smb
```

## Remover acesso de usuario

```bash
smbpasswd -d usuario
gpasswd -d usuario siha_faturamento
```

## Nao apagar dados sem backup

Nao remova `/dados/siha` durante rollback operacional. Primeiro valide backup,
snapshot e necessidade administrativa.
