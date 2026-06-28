---
data: <AAAA-MM-DD>
ambiente: <ambiente>
alvo: <CTID/VMID/hostname/servico>
status: <parcial|validado|falhou>
---

# Relatorio de validacao - <operacao>

## Resumo

Descreva em uma frase o que foi validado e o resultado.

## Escopo validado

- Alvo:
- Scripts/comandos:
- Dados sinteticos usados:
- Dados reais afetados: `<nenhum|descrever>`

## Evidencias

| Item | Evidencia | Resultado |
|---|---|---|
| Estrutura | `<comando ou arquivo>` | `<ok/falha>` |
| Servico | `<comando ou log>` | `<ok/falha>` |
| Funcional | `<teste executado>` | `<ok/falha>` |
| Backup | `<arquivo/ID>` | `<ok/falha/N/A>` |
| Restore | `<alvo descartavel>` | `<ok/falha/N/A>` |

## Comandos executados

```powershell
<comandos principais>
```

## Resultado observado

```text
<saida relevante sem segredos>
```

## Falhas e correcoes

- `<falha encontrada, causa, correcao aplicada ou pendencia>`

## Riscos residuais

- `<risco operacional, impacto e mitigacao>`

## Aceite

- [ ] Validacoes passaram.
- [ ] Logs revisados.
- [ ] Backup/restore testado quando aplicavel.
- [ ] Documentacao atualizada.
- [ ] Nada sensivel foi registrado.
