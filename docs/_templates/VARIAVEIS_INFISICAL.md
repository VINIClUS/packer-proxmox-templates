# Variaveis Infisical - <area>

Path: `<exemplo: /test/Monitoring>`
Ambiente: `<dev/test/prod>`
Projeto: `<slug ou workspace>`

Nunca registre valores reais de senhas, tokens, chaves privadas ou dados sensiveis neste documento.

## Variaveis

| Chave | Sensivel | Origem local | Uso | Observacao |
|---|---:|---|---|---|
| `<NOME_DA_VARIAVEL>` | `<sim|nao>` | `<.env|manual|gerado>` | `<servico/script>` | `<observacao>` |

## Sync

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script-de-sync> -DryRun
rtk powershell -NoProfile -ExecutionPolicy Bypass -File <script-de-sync>
```

O relatorio do sync deve mostrar apenas path, acao e `valuePresent`, nunca o valor.

## Validacao

- [ ] Path existe no Infisical.
- [ ] Chaves nao sensiveis conferem com a documentacao.
- [ ] Chaves sensiveis existem com valor preenchido.
- [ ] Arquivos `.example` rastreados foram atualizados.
- [ ] Nenhum valor real foi commitado.
