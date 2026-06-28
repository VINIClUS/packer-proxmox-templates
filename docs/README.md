# Documentacao do repositorio

Este diretorio reune runbooks, relatorios de validacao, inventarios,
credenciais documentadas sem segredos e templates de operacao. Ele e parte do
artefato operacional: mudancas em scripts, backups, restores, jobs,
agendamentos, rotinas administrativas ou variaveis devem atualizar a
documentacao correspondente no mesmo commit.

## Padrao obrigatorio

Use estes pontos de entrada antes de criar ou alterar uma rotina operacional:

- `AGENTS.md`: regra geral para agentes e contribuidores.
- `.agents/skills/documentar-operacao/SKILL.md`: checklist reutilizavel.
- `docs/_templates/`: modelos para operacao, implantacao, validacao e
  variaveis Infisical.

O tom padrao e portugues brasileiro procedural, com escopo claro, comandos
exatos, criterios de validacao, rollback preservando dados, seguranca e
evidencias. Nunca registre valores reais de senhas, tokens, chaves privadas,
certificados privados ou dados sensiveis.

## Mapa dos documentos

| Caminho | Uso |
|---|---|
| `docs/_templates/` | Modelos oficiais para novas documentacoes operacionais. |
| `docs/build-reports/` | Relatorios datados de builds e validacoes de templates. |
| `docs/credentials/` | Inventarios HTML de variaveis e credenciais sem valores reais. |
| `docs/esus-pec/` | Runbooks, planos, inventarios e evidencias do e-SUS PEC. |
| `docs/monitoring/` | Documentacao da stack de monitoramento. |
| `docs/setup-readonly/` | Inventarios e planos de leitura/analise sem alteracao. |
| `docs/siha-nas/` | Operacao do NAS SIHA, Samba, backup, restore e Windows. |
| `docs/superpowers/` | Planos e especificacoes auxiliares de implementacao. |

## Checklist para nova rotina

1. Identifique o dominio em `docs/` ou crie uma subpasta clara.
2. Copie o template mais proximo de `docs/_templates/`.
3. Preencha objetivo, escopo, topologia, variaveis e pre-requisitos.
4. Inclua dry-run quando existir e comandos reais com prefixo `rtk`.
5. Defina validacao objetiva, logs e caminhos de evidencia.
6. Documente impacto em backup/restore e rollback preservando dados.
7. Atualize arquivos `.example` quando houver variavel ou segredo novo.
8. Rode os testes/preflights relevantes e registre o resultado.

## Validacao documental

Execute a validacao estatica do padrao antes de finalizar mudancas de
documentacao operacional:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests\Validate-DocumentationStandard.ps1
```

Essa validacao nao substitui testes reais de build, restore, conectividade ou
interface; ela apenas garante que o padrao documental minimo continua presente.
