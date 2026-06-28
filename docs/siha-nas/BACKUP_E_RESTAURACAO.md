# Backup e restauracao

## Regra principal

O compartilhamento Samba nao e backup. Ele e o armazenamento de trabalho. Se a
VM Windows tiver permissao de escrita, um erro humano ou ransomware tambem pode
alterar ou apagar arquivos.

## Volume Proxmox gerenciado

Se `/dados/siha` estiver no rootfs ou em mount point Proxmox com `backup=1`, o
backup do container pode incluir os dados. Validar no host:

```bash
pct config CTID
```

Procure por `rootfs` e `mp0`. Se houver `mp0`, confirme se esta com `backup=1`.

## Bind mount do host

Se `/dados/siha` for bind mount do host, o backup do container pode nao incluir
os dados. Documente explicitamente:

- caminho no host;
- mapeamento UID/GID do LXC unprivileged;
- rotina de backup independente do host/dataset;
- como restaurar arquivo unico.

Nao assuma que UID 1000 dentro do container e UID 1000 no host. Leia:

```bash
pct config CTID
cat /proc/self/uid_map
cat /proc/self/gid_map
```

Em LXC unprivileged, o ownership no host costuma usar faixa deslocada. Ajuste
permissoes no host com base no mapa real, nao por chute.

## Estrategia minima

- Snapshot local antes de atualizacoes.
- Backup semanal para armazenamento que a VM Windows nao consegue escrever.
- Retencao semanal rotativa de 4 semanas.
- Teste de restauracao periodico.
- Copia externa/offline ou imutavel quando disponivel.
- Monitoramento de falha de backup.

## Retencao aprovada

- Frequencia: semanal.
- Retencao: 4 backups semanais rotativos.
- Destino: storage de backup nao gravavel pela VM Windows.
- Escopo atual: CT `7010`, incluindo `/dados/siha` dentro do rootfs em `rpool`.
- Teste: restaurar pelo menos um backup em CT descartavel antes de considerar a politica operacionalmente aceita.
- Copia externa/offline: recomendada quando houver armazenamento disponivel.

Comando modelo para backup manual:

```bash
vzdump 7010 --mode snapshot --storage local --compress zstd --notes-template 'siha-nas weekly backup'
```

Ao configurar job recorrente no Proxmox, manter 4 copias semanais e validar que o job inclui o CT `7010`.

## Restauracao de arquivo unico

1. Identifique o caminho no indice anual.
2. Restaure para uma pasta temporaria, nunca por cima do arquivo atual.
3. Confira hash SHA256 quando houver manifesto.
4. Peça validacao da equipe de faturamento.
5. Mova para o local definitivo mantendo nome compreensivel.

## Restauracao de compactado antigo

1. Verifique o hash em `99_MANIFESTOS_HASHES`.
2. Extraia para uma area temporaria.
3. Compare com o relatorio de arquivamento.
4. Restaure apenas os arquivos necessarios.

## Teste de restauracao

Registre em `98_RELATORIOS_DE_AUDITORIA`:

- data do teste;
- origem do backup;
- arquivo restaurado;
- tempo de restauracao;
- responsavel;
- resultado;
- hash antes/depois, quando aplicavel.
