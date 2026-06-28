---
name: documentar-operacao
description: Use esta skill sempre que uma tarefa alterar scripts operacionais, provisionamento, backups, restores, jobs, timers, agendamentos, rotinas administrativas, variaveis Infisical ou runbooks de infraestrutura. Ela força a documentacao operacional no mesmo commit, com comandos exatos, validacao, rollback, backup/restore, seguranca e evidencias, mesmo quando o usuario nao pedir explicitamente documentacao.
---

# Documentar Operacao

Use esta skill para manter o repositorio operavel por outra pessoa depois da automacao ser entregue. A documentacao deve explicar como executar, validar, auditar e desfazer a rotina sem depender do historico do chat.

## Quando aplicar

Acione este fluxo quando a tarefa tocar qualquer um destes pontos:

- scripts de provisionamento, instalacao, sync, migracao ou manutencao;
- backups, restores, snapshots, compactacao, retencao ou rotacao;
- jobs, timers systemd, cron, agendamentos ou automacoes recorrentes;
- rotinas administrativas de CT/VM/servicos;
- variaveis Infisical, `.env.example`, credenciais, tokens ou caminhos de segredo;
- runbooks de implantacao, validacao, troubleshooting ou rollback.

## Fluxo obrigatorio

1. Inspecione a documentacao operacional existente antes de editar.
   - Leia documentos proximos ao alvo em `docs/`.
   - Leia `docs/README.md` para localizar o dominio documental correto.
   - Reaproveite o tom local: portugues brasileiro operacional, comandos exatos, checklists, evidencias e riscos.
   - Use `docs/_templates/` quando criar documento novo.

2. Durante a implementacao, mantenha a documentacao junto da mudanca.
   - Se alterar script, atualize o runbook que o executa.
   - Se alterar backup/restore, atualize procedimento de restore e criterio de aceite.
   - Se alterar job/timer, documente frequencia, comando, logs, dry-run e rollback.
   - Se alterar segredo ou variavel, atualize arquivo `.example`, path Infisical e tabela de variaveis sem valores reais.

3. Nunca exponha segredos.
   - Nao coloque senhas, tokens, chaves privadas ou dados sensiveis em docs, logs, chat ou argumentos de linha de comando.
   - Relatorios de sync devem mostrar apenas path, nome da chave, acao e presenca de valor.

4. Inclua criterios de validacao concretos.
   - Comandos exatos com `rtk`.
   - Resultado esperado ou evidencia observada.
   - Logs e caminhos de relatorio.
   - Teste de backup/restore quando houver dados persistentes.
   - Aviso explicito quando algo ainda nao esta pronto para producao.

5. Antes de finalizar, confira consistencia.
   - `rtk git diff --check`.
   - Testes/syntax checks relevantes.
   - Verifique que os documentos citam os scripts e parametros atuais.
   - Verifique que nenhum segredo foi adicionado ao diff.

## Secoes esperadas

Para documentos operacionais novos ou revisados, cubra:

- Objetivo/Escopo.
- Topologia, campos de implantacao ou variaveis.
- Pre-requisitos e checagens de seguranca.
- Execucao com dry-run quando existir.
- Validacao com resultado esperado.
- Backup e restauracao.
- Rollback preservando dados por padrao.
- Seguranca, firewall, exposicao e menor privilegio.
- Evidencias, logs e relatorios.
- Aceite final e pendencias.

## Templates

Use estes arquivos como ponto de partida:

- `docs/_templates/CHECKLIST_DOCUMENTACAO_OPERACIONAL.md`
- `docs/_templates/OPERACAO_ADMINISTRATIVA.md`
- `docs/_templates/PLANO_IMPLANTACAO.md`
- `docs/_templates/RELATORIO_VALIDACAO.md`
- `docs/_templates/VARIAVEIS_INFISICAL.md`

Adapte os templates ao contexto em vez de copiar secoes vazias sem valor operacional.

## Resposta final

Ao finalizar uma tarefa operacional, informe de forma curta:

- arquivos de script/config alterados;
- documentos atualizados;
- comandos de validacao executados;
- testes reais que ainda faltam, especialmente producao, acesso cliente e restore.
