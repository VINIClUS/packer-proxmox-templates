# <Nome da operacao administrativa>

Data: `<AAAA-MM-DD>`
Ambiente: `<Proxmox/CT/VM/servico>`
Responsavel operacional: `<nome ou equipe>`
Status: `<rascunho|aprovado|executado|validado>`

## Objetivo

Explique o que esta operacao muda, por que ela existe e qual problema operacional resolve.

## Escopo

- Alvos: `<CTID/VMID/hostname/IP/servico>`
- Fora do escopo: `<itens explicitamente nao alterados>`
- Dados afetados: `<nenhum|configuracao|backup|arquivos de usuario|banco de dados>`

## Variaveis e caminhos

| Campo | Valor |
|---|---|
| CTID/VMID | `<preencher>` |
| Hostname | `<preencher>` |
| IP/CIDR | `<preencher>` |
| Gateway/DNS | `<preencher>` |
| Storage | `<preencher>` |
| Scripts | `<preencher>` |
| Logs | `<preencher>` |
| Infisical path | `<preencher ou N/A>` |

## Pre-requisitos e seguranca

- [ ] `rtk git status --short` revisado.
- [ ] Credenciais necessarias existem em `.env` ou Infisical, sem imprimir valores.
- [ ] Dry-run executado quando disponivel.
- [ ] Janela operacional aprovada, se houver impacto.
- [ ] Backup ou snapshot confirmado quando a operacao puder alterar dados.
- [ ] Portas expostas e firewall revisados.

## Execucao

Primeiro executar dry-run, quando suportado:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script> -DryRun
```

Execucao real:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script> <parametros>
```

Nao coloque senhas, tokens ou chaves privadas em argumentos de linha de comando.

## Validacao

| Validacao | Comando | Resultado esperado |
|---|---|---|
| Sintaxe | `rtk powershell -NoProfile -ExecutionPolicy Bypass -File <teste>` | `<mensagem esperada>` |
| Servico ativo | `<comando>` | `<active/running/ok>` |
| Acesso funcional | `<comando>` | `<resultado esperado>` |
| Logs | `<comando>` | `<sem erros novos>` |

## Backup e restauracao

Descreva se a operacao altera dados persistentes. Quando alterar, registre:

- caminho do backup;
- comando usado para gerar backup;
- destino de restore descartavel;
- evidencias de restore validado;
- retencao aprovada.

## Rollback

Procedimento para parar, desfazer ou isolar a mudanca preservando dados por padrao.

```powershell
<comandos de rollback>
```

## Evidencias

- Logs:
- Relatorios:
- Arquivos alterados:
- Commit/tag:

## Aceite

- [ ] Execucao concluida sem erro.
- [ ] Validacoes funcionais passaram.
- [ ] Backup/restore testado quando aplicavel.
- [ ] Documentacao atualizada no mesmo commit.
- [ ] Pendencias e riscos foram registrados.

## Pendencias

- `<item manual ou risco residual>`
