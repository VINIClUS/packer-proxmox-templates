```markdown
# 📦 Packer Proxmox Templates

Este repositório contém a infraestrutura como código (IaC) necessária para construir, selar e versionar **Golden Images** automatizadas para o hypervisor Proxmox VE, utilizando o HashiCorp Packer.

## 🎯 Propósito

O objetivo principal deste projeto é garantir que todas as máquinas virtuais (Linux e Windows) provisionadas no ambiente Proxmox nasçam de templates **imutáveis, auditáveis e 100% reproduzíveis**. Ao eliminar a intervenção manual ("clicar em avançar" na instalação), mitigamos falhas de segurança, desvios de configuração (configuration drift) e aceleramos o tempo de deploy de novas aplicações.

## 🛠️ Stack de Ferramentas Escolhidas

*   **HashiCorp Packer:** Orquestrador de build. Lê as declarações HCL e automatiza a criação da VM, injeção de ISO, boot via VNC e exportação do template final no Proxmox.
*   **Proxmox VE (PVE):** Hypervisor de destino via API (`proxmox-iso` builder).
*   **Respostas Desacompanhadas (Unattended):** 
    *   `Autounattend.xml` para a stack Windows.
    *   `preseed.cfg` para a stack Debian-based.
    *   `ks.cfg` (Kickstart) para a stack RHEL-based.
*   **Sysprep & Cloud(base)-Init:** Motores de generalização e inicialização. Garantem que a imagem selada possa receber metadados dinâmicos (IP, hostname, chaves SSH) assim que for clonada.
*   **Codex CLI (AI Coding Agent):** Assistente de inteligência artificial primário utilizado para refatoração, manutenção e evolução dos scripts deste repositório.

---

## 📂 Estrutura do Repositório

A arquitetura do repositório separa estritamente a configuração global, componentes compartilhados e especificidades de cada Sistema Operacional.

```text
packer-proxmox-templates/
├── config/             # Configurações globais e credenciais do Hypervisor.
├── shared/             # Scripts cross-OS (ex: validação de rede, webhooks de notificação).
├── windows/            # Definições de build para a stack Microsoft.
│   └── [versão]/       
│       ├── http/       # Arquivos servidos pelo servidor HTTP embutido do Packer no momento do boot.
│       └── scripts/    # Scripts pós-instalação (bloatware removal, winrm, sysprep).
└── linux/              # Definições de build para distribuições Linux.
    └── [distro]/
        ├── http/       # Arquivos de resposta preseed/kickstart.
        └── scripts/    # Hardening e limpeza (limpeza de chaves SSH, machine-id, logs).

```

---

## 🔒 Boas Práticas e Segurança

1. **Imutabilidade Estrita:** Templates não sofrem manutenção. Se um template Windows Server 2022 precisa das atualizações deste mês, altera-se a ISO de origem ou executa-se o pipeline novamente. Nunca ligue um template manualmente para aplicar patches.
2. **Segregação de Segredos:** O arquivo `config/Proxmox.pkrvars.hcl` contém tokens de API e senhas. Ele está explicitamente no `.gitignore`. **Nunca commite credenciais no controle de versão.**
3. **Clean State (Estado Limpo):** Todos os scripts na pasta `scripts/` de cada OS devem focar em deixar a máquina genérica. No Linux, isso inclui truncar o `/etc/machine-id` e remover o histórico bash. No Windows, inclui generalizar via `sysprep.exe`.

---

## 🤖 Diretrizes para o Codex CLI (AI Agent Context)

> **Nota ao Agente de IA:** Leia estas regras cuidadosamente antes de propor modificações neste repositório.

* **Linguagem Principal:** Utilize sintaxe **HCL2** para todos os arquivos Packer (`.pkr.hcl`). Não crie templates no formato antigo JSON.
* **Padrão de Variáveis:** Sempre que criar um novo parâmetro de configuração, declare-o primeiro em `variables.pkr.hcl` e nunca faça hardcode no arquivo de build principal.
* **Segurança Primeiro:** Se o usuário solicitar a adição de uma senha ou token, instrua-o a colocar a variável no arquivo `config/Proxmox.pkrvars.hcl` e referencie-a no código apenas usando o bloco `var.<nome_da_variavel>`.
* **Idempotência:** Scripts Powershell (`.ps1`) ou Bash (`.sh`) criados na pasta `scripts/` devem ser idempotentes e falhar silenciosamente se o recurso já estiver no estado desejado.
* **Comunicação com Proxmox:** Ao gerar configurações de hardware para as VMs (`proxmox-iso`), utilize as flags modernas: defina o Qemu Agent como ativo (`qemu_os = "l26"` para Linux, `qemu_os = "win11"` para Win11), e prefira discos `scsi` em conjunto com a controladora `virtio-scsi-single`.

---

## 🚀 Como Executar Localmente

1. Crie seu arquivo de variáveis globais a partir do template (se houver) e preencha com as credenciais do Proxmox:

```bash
   touch config/Proxmox.pkrvars.hcl

```

2. Inicialize os plugins do Packer no diretório alvo:

```bash
   packer init ./windows/server-2022

```

3. Valide a sintaxe (Sempre execute isso antes do build):

```bash
   packer validate -var-file="config/Proxmox.pkrvars.hcl" ./windows/server-2022

```

4. Execute o build:

```bash
   packer build -var-file="config/Proxmox.pkrvars.hcl" ./windows/server-2022

```

```

### O que torna este documento ideal para um cenário com Agente de IA:

1. **A Seção de Diretrizes (AI Agent Context):** Agentes leem arquivos README e CONTRIBUTING nativamente para entender o "System Prompt" implícito daquele workspace. Ao colocar regras sobre HCL2, hardcode e uso de SCSI/Virtio ali, você poupa tokens em cada prompt seu, pois a IA já sabe como o repositório deve se comportar.
2. **Definição Clara de Responsabilidades:** O agente entende rapidamente que a pasta http/ serve apenas para o momento de *boot* e a pasta scripts/ serve para o *provisionamento*. Ele não vai tentar jogar um script .ps1 no lugar errado. 

<FollowUp label="Quer elaborar os arquivos base do Packer?" query="Crie a estrutura básica do arquivo windows-2022.pkr.hcl utilizando as melhores práticas para o builder proxmox-iso."/>

```