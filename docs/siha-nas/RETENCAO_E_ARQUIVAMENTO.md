# Retencao e arquivamento

## Politica

Arquivos com mais de 730 dias podem ser candidatos a arquivo morto. A politica
e conservadora: a primeira execucao deve gerar relatorio, nao apagar nada.

## Nunca compactar automaticamente

- `00_LEIA-ME`
- `05_DOCUMENTACAO_OPERACIONAL`
- `98_RELATORIOS_DE_AUDITORIA`
- `99_MANIFESTOS_HASHES`
- `.lixeira`
- arquivos temporarios, locks e caches
- arquivos ja compactados
- backup mais recente de cada sistema

## Formatos

### zip

Vantagens:

- abre facilmente no Windows;
- bom para operacao cotidiana;
- simples para restauracao por usuario administrativo.

Desvantagens:

- compressao menor que `tar.zst`;
- menos eficiente em muitos arquivos pequenos.

### tar.zst

Vantagens:

- compressao melhor;
- bom para arquivo administrativo grande.

Desvantagens:

- normalmente exige ferramenta extra no Windows;
- menos conveniente para restauracao por equipe nao tecnica.

Default: `zip`.

## Relatorio somente

```bash
arquivar-antigos-siha.sh --report-only --older-than-days 730
```

## Dry-run

```bash
arquivar-antigos-siha.sh --dry-run --year 2024 --format zip
```

Dry-run nao grava relatorios, compactados, hashes nem logs. Ele lista o que
seria candidato e termina sem mutar dados. Para registrar um relatorio mensal
sem compactar, use `--report-only`.

## Compactar mantendo originais

```bash
arquivar-antigos-siha.sh --year 2024 --format zip
```

O script agrupa por ano e categoria para evitar um unico ZIP gigante. Antes de
compactar, ele ignora arquivos recentes, temporarios, ja compactados, lixeira,
arquivos cujo tamanho/mtime ainda esta mudando e o backup mais recente de cada
sistema quando a deteccao for segura.

## Remover originais

Somente apos revisao do relatorio, teste do compactado, hash registrado e
backup valido:

```bash
arquivar-antigos-siha.sh --year 2024 --format zip --remove-originals-after-verify
```

## Destino

```text
/dados/siha/91_ARQUIVO_COMPACTADO/AAAA/SIHA_ARQUIVO_AAAA_CATEGORIA.zip
```

Hashes ficam em:

```text
/dados/siha/99_MANIFESTOS_HASHES/
```

Relatorios ficam em:

```text
/dados/siha/98_RELATORIOS_DE_AUDITORIA/
```
