# Convencao de nomes SIHA

## Padrao

Use:

```text
AAAA-MM-DD_SISTEMA_COMPETENCIA_TIPO_ORIGEM-OU-DESTINO_DESCRICAO_STATUS.ext
```

Exemplo:

```text
2026-06-28_SIHA_2026-05_REMESSA_MS_ENVIO-OFICIAL.zip
```

## Por que iniciar com data

A data no inicio faz o Windows, o Samba e os indices ordenarem os arquivos por
evento. Isso reduz ambiguidade quando alguem procurar o historico depois de
anos.

## Data, competencia e recebimento

- Data inicial: dia em que o evento aconteceu ou foi registrado.
- Competencia: mes de faturamento, no formato `AAAA-MM`.
- Data de recebimento: use no inicio do nome quando o arquivo for retorno ou
  protocolo recebido.

Um protocolo recebido em 2026-06-29 para a competencia 2026-05 deve ser:

```text
2026-06-29_SIHA_2026-05_PROTOCOLO_MS_RECEBIDO.pdf
```

## Remessa

```text
2026-06-28_SIHA_2026-05_REMESSA_MS_ENVIO-OFICIAL.zip
```

Use `REMESSA_MS` e indique se e `ENVIO-OFICIAL`, `REENVIO`,
`RETIFICADORA` ou `TESTE`.

## Retorno

```text
2026-07-01_SIHA_2026-06_RETORNO_MS_PROCESSADO.xml
```

Use `RETORNO_MS` e descreva o status: `RECEBIDO`, `PROCESSADO`,
`COM-ERRO`, `VALIDADO`.

## Protocolo

```text
2026-06-29_SIHA_2026-05_PROTOCOLO_MS_RECEBIDO.pdf
```

Use `PROTOCOLO_MS` e mantenha a competencia original.

## Backup

```text
2026-06-30_SIHA_2026-05_BACKUP_SISTEMA_POS-FECHAMENTO.bak
```

Inclua o sistema e o momento: `PRE-ATUALIZACAO`, `POS-FECHAMENTO`,
`PRE-IMPORTACAO`, `POS-IMPORTACAO`.

## Arquivo compactado

Arquivos gerados pelo arquivamento usam:

```text
SIHA_ARQUIVO_AAAA_CATEGORIA.zip
SIHA_ARQUIVO_AAAA_CATEGORIA.tar.zst
```

Prefira `.zip` quando a equipe precisar abrir pelo Windows sem ferramentas
extras. Use `.tar.zst` apenas para administracao, quando compressao maior for
mais importante que conveniencia.

## Exemplos bons

- `2026-06-28_SIHA_2026-05_REMESSA_MS_ENVIO-OFICIAL.zip`
- `2026-06-29_SIHA_2026-05_PROTOCOLO_MS_RECEBIDO.pdf`
- `2026-06-30_SIHA_2026-05_BACKUP_SISTEMA_POS-FECHAMENTO.bak`
- `2026-07-01_SIHA_2026-06_RETORNO_MS_PROCESSADO.xml`
- `2026-07-02_SIHA_2026-06_RELATORIO_AUDITORIA_CONFERENCIA-ACENTUACAO.pdf`
- `2026-07-03_SIHA_2026-06_DOCUMENTACAO_INTERNA_ARQUIVOS-COM-ESPACO-E-ACENTO.md`

## Exemplos ruins

- `backup.bak`
- `retorno.xml`
- `final.zip`
- `arquivo antigo.pdf`
- `competencia maio certo agora.zip`

Esses nomes nao explicam data, sistema, competencia, tipo, origem/destino ou
status.

## Arquivos com espaco, acentuacao e CSV injection

O armazenamento aceita arquivos com espaco e acentuacao, mas prefira hifen em
vez de espacos nos nomes novos. Os indices CSV protegem campos que comecam com
`=`, `+`, `-`, `@` ou tab para mitigar CSV injection em planilhas. Mesmo assim,
nao crie nomes como `=formula.csv`, `+soma.csv`, `-comando.csv` ou
`@externo.csv`.

## Como procurar arquivos antigos

1. Comece pela competencia `AAAA-MM`.
2. Filtre pelo tipo: `REMESSA_MS`, `RETORNO_MS`, `PROTOCOLO_MS`, `BACKUP`.
3. Consulte `99_MANIFESTOS_HASHES/indice_AAAA.csv`.
4. Consulte relatorios em `98_RELATORIOS_DE_AUDITORIA`.
5. Se o arquivo tiver mais de dois anos, procure tambem em
   `91_ARQUIVO_COMPACTADO/AAAA/`.
