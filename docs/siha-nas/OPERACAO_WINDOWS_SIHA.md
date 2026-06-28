# Operacao Windows SIHA

## Acesso

Share principal:

```text
\\siha-nas\SIHA
```

Unidade sugerida:

```text
S:
```

## Mapeamento

Na VM Windows 11 `SIHA`, execute:

```powershell
PowerShell -ExecutionPolicy Bypass -File scripts\windows\mapear-siha-nas.ps1
```

O script:

- testa `siha-nas:445`;
- cria mapeamento persistente;
- nao grava senha em texto puro;
- pode ser reexecutado se `S:` ja apontar para o share certo.

Se o mapeamento existir mas nao aparecer no Explorer do operador, verificar a
separacao de tokens elevados do Windows. O ambiente foi ajustado com:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
EnableLinkedConnections = 1
```

Apos esse ajuste, faca logoff/login do usuario operacional ou reinicie o
Explorer para o Windows materializar a unidade no shell grafico.

## Credenciais

Use o usuario Samba autorizado. Para salvar credenciais sem colocar senha em
script, use o Gerenciador de Credenciais do Windows:

```powershell
cmdkey /add:siha-nas /user:siha_user /pass
```

O Windows vai solicitar a senha no console.

## Teste simples

1. Abra `S:`.
2. Crie `00_LEIA-ME\teste_mapeamento.txt`.
3. No container, valide:

```bash
ls -l /dados/siha/00_LEIA-ME/teste_mapeamento.txt
```

4. Apague o arquivo pelo Windows.
5. Verifique `.lixeira/siha_user` para confirmar recycle bin.

## Cuidados

- Nao salve senhas no share.
- Nao trabalhe diretamente em arquivo compactado antigo.
- Copie arquivos antigos para area temporaria antes de editar.
- Em caso de suspeita de ransomware, desligue a VM da rede e preserve o NAS.
