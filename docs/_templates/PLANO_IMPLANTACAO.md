# Plano de implantacao - <servico>

Este plano deve ser preenchido antes de executar uma implantacao real. Ele deve permitir que outra pessoa execute a mudanca, valide o resultado e volte atras sem depender do historico do chat.

## Campos da implantacao

| Campo | Valor aprovado |
|---|---|
| Ambiente | `<teste|homologacao|producao>` |
| CTID/VMID | `<preencher>` |
| Hostname | `<preencher>` |
| IP/CIDR | `<preencher>` |
| Gateway | `<preencher>` |
| DNS | `<preencher>` |
| Storage rootfs | `<preencher>` |
| Storage dados | `<preencher>` |
| Tipo de mount point | `<rootfs|mpN|bind mount|dataset>` |
| Politica de backup | `<preencher>` |
| Usuario inicial | `<preencher>` |
| Cliente/consumidor | `<preencher>` |
| Portas/rede permitidas | `<preencher>` |
| Infisical path | `<preencher>` |

## Checklist pre-producao

- [ ] Campos acima preenchidos.
- [ ] `rtk git status --short` revisado.
- [ ] Commit/tag da versao registrado.
- [ ] CTID/VMID livre ou plano de substituicao aprovado.
- [ ] IP/DNS livres e reservados.
- [ ] Storage com espaco suficiente.
- [ ] Segredos presentes em Infisical ou `.env`, sem valores em arquivos rastreados.
- [ ] Backup e restore testados antes de dados reais.
- [ ] Dry-run revisado.
- [ ] Rollback documentado.

## Comandos de versao

```powershell
rtk git status --short
rtk git rev-parse --abbrev-ref HEAD
rtk git rev-parse HEAD
rtk git tag --points-at HEAD
rtk git diff --check
```

## Dry-run

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script> <parametros> -DryRun
```

## Execucao

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script> <parametros>
```

## Validacao

```powershell
<comandos de validacao estrutural>
<comandos de validacao de servico>
<comandos de validacao funcional>
```

Resultado esperado:

```text
<sinais concretos de sucesso>
```

## Backup e restore obrigatorios

Antes de uso com dados reais:

1. Criar dado sintetico.
2. Executar backup.
3. Restaurar em alvo descartavel.
4. Validar leitura, permissoes, logs e integridade.
5. Remover alvo descartavel.
6. Registrar caminho do backup e resultado.

## Rollback

```powershell
<parar servico ou CT/VM>
<desfazer mapeamentos ou integracoes>
<preservar dados>
<remover somente se vazio ou apos backup aprovado>
```

## Aceite final

- [ ] Implantacao executada.
- [ ] Validacao estrutural passou.
- [ ] Validacao funcional passou.
- [ ] Backup/restore passou.
- [ ] Documentacao e variaveis de exemplo atualizadas.
- [ ] Riscos residuais aceitos.
