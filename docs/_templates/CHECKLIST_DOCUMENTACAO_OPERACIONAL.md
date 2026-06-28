# Checklist de documentacao operacional

Use este checklist antes de finalizar qualquer alteracao em scripts,
provisionamento, backups, restores, jobs, timers, agendamentos, rotinas
administrativas ou variaveis operacionais.

## Escopo

- [ ] O dominio afetado foi identificado em `docs/`.
- [ ] A mudanca tem objetivo e fora-do-escopo claros.
- [ ] Alvos foram descritos com CTID/VMID, hostname, IP, path, storage ou
      servico quando aplicavel.

## Documentos

- [ ] Runbook atualizado ou criado a partir de `docs/_templates/`.
- [ ] Plano de implantacao atualizado quando houver execucao real.
- [ ] Relatorio de validacao atualizado quando houver teste executado.
- [ ] Inventario de variaveis atualizado sem valores reais.
- [ ] `docs/README.md` continua apontando para o local correto.

## Seguranca

- [ ] Nenhuma senha, token, chave privada ou dado sensivel entrou no diff.
- [ ] Variaveis novas foram adicionadas a arquivos `.example` rastreados.
- [ ] Namespace Infisical correto foi documentado.
- [ ] Producoes protegidas continuam leitura por padrao, salvo autorizacao
      explicita.

## Execucao e validacao

- [ ] Comandos usam prefixo `rtk`.
- [ ] Dry-run ou modo seguro foi documentado quando existir.
- [ ] Resultado esperado e criterio de aceite foram definidos.
- [ ] Logs, relatorios e evidencias tem caminhos concretos.
- [ ] Backup/restore foi documentado e testado quando ha dados persistentes.
- [ ] Rollback preserva dados por padrao.

## Commit

- [ ] Script/config, documentacao, exemplos e testes pertencem ao mesmo escopo.
- [ ] Mudancas nao relacionadas ficaram fora do commit.
- [ ] `rtk git diff --check` passou.
- [ ] Testes/preflights relevantes passaram ou a limitacao foi documentada.
