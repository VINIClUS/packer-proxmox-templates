Abaixo está uma **Spec pronta para colar no Codex CLI**. Ela foi escrita para um agente com acesso ao node Proxmox, mas com **modo supervisionado**, validação ponto a ponto e bloqueio explícito contra alterações destrutivas sem autorização. O Codex CLI pode ler, alterar e executar comandos no diretório selecionado, então a Spec força uma primeira fase somente de análise antes de qualquer mudança real.

---

# SPEC — Plataforma segura para publicação e gestão de aplicação em CT no Proxmox

## 1. Contexto

Estamos operando um ambiente Proxmox VE com o node atual `pve-01`. Pelo inventário visual existente, há pelo menos os seguintes recursos:

```text
Node: pve-01

CTs existentes:
- 100: Netbird
- 110: nginx
- 120: infiscal / aplicação alvo

VMs/templates:
- 101: ESUS-TESTE
- 9101: tp-win11-24h2
- 9200: tp-debian-13-cloudinit
- 9201: tp-almalinux-10-cloudinit
- 9202: tp-ubuntu-26.04-cloudinit

Storages:
- localnetwork
- local
- local-lvm
- rpool
```

### 1.1 Contexto específico do app e-SUS PEC

O arquivo `appEsusPEC.md` aponta para uma fonte complementar sobre a instalação
e recuperação do e-SUS PEC em Debian 13. Essa fonte adiciona requisitos
operacionais que devem ser tratados antes de qualquer publicação via reverse
proxy:

```text
- O sistema operacional observado para o app é Debian 13.
- O instalador Java `.jar` do e-SUS PEC pode falhar em ambiente Wayland com
  "No X11 DISPLAY variable was set".
- O caminho preferencial para servidor deve ser instalação headless/console,
  quando suportada pelo instalador, evitando dependência de GUI.
- PostgreSQL, psql e pg_restore precisam ser inventariados antes de qualquer
  restauração.
- Arquivos `.backup` do PostgreSQL devem ser classificados com `file` antes de
  escolher `pg_restore` ou `psql`.
- Restauração de banco, parada de serviço e alterações de partição/swap são
  ações destrutivas ou disruptivas e exigem autorização explícita.
- Backups oficiais do e-SUS PEC podem incluir banco de dados e mídias/galeria;
  ambos devem ser localizados antes de qualquer restore.
- Expansão de disco no Proxmox pode exigir rescan, growpart, resize2fs/xfs_growfs
  e, se swap em partição bloquear crescimento, preferir swapfile após aprovação.
```

### 1.2 Correções de inventário conhecidas

O inventário read-only de 2026-05-25 registrou os nomes atuais observados no
Proxmox:

```text
Node/IP observado:
- Proxmox em 192.168.1.149

CTs existentes:
- 100: Netbird
- 110: nginx
- 120: infisical

VMs/templates:
- 101: ESUS-TESTE
- 9101: tpl-win11-24h2
- 9200: tpl-debian-13-cloudinit
- 9201: tpl-almalinux-10-cloudinit
- 9202: tpl-ubuntu-26-04-cloudinit
```

Antes de implementação, confirmar se `CT 120` é realmente a aplicação e-SUS PEC
ou se o e-SUS PEC está na VM `101 ESUS-TESTE`.

O objetivo é transformar esse ambiente em uma base operacional segura, auditável, automatizável e observável para disponibilizar uma aplicação via CT/VM, preferencialmente sem expor diretamente o CT da aplicação à internet.

A implementação deve considerar que o ambiente pertence a uma estrutura pública/municipal, portanto deve priorizar segurança, rastreabilidade, reversibilidade, baixo risco operacional e documentação clara.

## 2. Objetivos principais

### 2.1 Objetivo técnico

Disponibilizar a aplicação hospedada no CT `120` ou em CT/VM equivalente por meio de um **reverse proxy centralizado**, preferencialmente usando o CT `110` existente, mantendo a aplicação em rede privada e expondo publicamente apenas portas HTTP/HTTPS necessárias.

### 2.2 Objetivo operacional

Criar uma base para gestão contínua da aplicação com:

```text
- inventário do ambiente;
- documentação da topologia;
- regras de firewall;
- reverse proxy padronizado;
- health checks;
- backup/rollback;
- logs;
- métricas;
- procedimentos de validação antes e depois;
- plano de evolução para CI/CD, Ansible, Terraform/OpenTofu e observabilidade.
```

### 2.3 Objetivo de segurança

Reduzir superfície de ataque:

```text
- não expor o Proxmox 8006 à internet;
- não expor SSH público desnecessário;
- não expor banco de dados publicamente;
- não expor Grafana, Prometheus, Infisical, Git, Jenkins ou SonarQube publicamente;
- administração somente por VPN/NetBird;
- publicar apenas 80/443 via reverse proxy;
- aplicar firewall default-deny sempre que viável;
- validar rollback antes de mudanças permanentes.
```

## 3. Motivações

A arquitetura atual com CTs individuais no Proxmox pode funcionar bem, mas sem padronização tende a gerar riscos:

```text
- dificuldade de saber quais portas estão abertas;
- exposição acidental de serviços internos;
- ausência de rollback claro;
- dificuldade de auditar alterações;
- deploys manuais não reproduzíveis;
- baixa visibilidade de erros;
- dificuldade de migrar futuramente para HA, DR, CI/CD ou Kubernetes.
```

A proposta é evoluir em etapas, sem superdimensionar. O ambiente atual não exige Kubernetes imediatamente. A primeira meta é ter uma base segura e repetível usando Proxmox, CT/VM, reverse proxy, firewall, backup e observabilidade.

## 4. Princípios obrigatórios

O agente deve seguir estes princípios durante toda a execução:

```text
1. Não executar mudanças destrutivas sem aprovação explícita.
2. Não reiniciar CTs, VMs, rede, firewall ou node sem informar impacto e pedir confirmação.
3. Não alterar rotas, bridges, interfaces, iptables/nftables, firewall Proxmox ou configuração de rede sem plano de rollback.
4. Não remover arquivos, pacotes, containers, volumes ou configurações existentes sem backup.
5. Não sobrescrever configurações existentes sem salvar cópia com timestamp.
6. Não publicar novas portas na internet sem validação explícita.
7. Não instalar Kubernetes, Jenkins, SonarQube, Grafana, Prometheus ou Loki nesta primeira fase sem autorização separada.
8. Priorizar mudanças pequenas, testáveis e reversíveis.
9. Produzir documentação em Markdown de tudo que for encontrado e alterado.
10. Ao final de cada fase, parar e apresentar relatório antes de avançar.
```

## 5. Escopo desta primeira implementação

### Dentro do escopo

```text
- inventariar o node Proxmox;
- identificar CTs, VMs, storages, bridges, IPs e rotas;
- identificar estado atual do CT 110 nginx;
- identificar estado atual do CT 120 aplicação;
- mapear portas abertas;
- mapear serviços ativos;
- mapear regras de firewall existentes;
- propor e, após aprovação, aplicar configuração de reverse proxy;
- criar health checks locais;
- criar documentação operacional;
- criar plano de backup/rollback;
- validar acesso interno e externo;
- recomendar próximos passos para CI/CD e observabilidade.
- inventariar requisitos do e-SUS PEC: Java, modo console/headless, PostgreSQL,
  backup/restore, mídia/galeria, disco e swap;
- classificar qualquer restore de banco e alteração de disco como ação
  disruptiva que exige aprovação separada.
```

### Fora do escopo inicial

```text
- implantação de cluster Proxmox;
- implantação de Ceph;
- implantação de Kubernetes/K3s;
- implantação de Jenkins;
- implantação de SonarQube;
- migração de banco de dados;
- restauração de backup e-SUS PEC sem janela aprovada;
- alteração de partições, swap ou `/etc/fstab` sem janela aprovada;
- alteração de storage;
- alteração profunda de rede física;
- configuração de failover Brasil/Alemanha;
- hardening completo CIS;
- automação Terraform/OpenTofu completa.
```

Esses itens podem virar fases posteriores.

## 6. Entregáveis obrigatórios

Criar um diretório de trabalho no node, preferencialmente:

```bash
/root/proxmox-app-platform-spec
```

Dentro dele, gerar os seguintes arquivos:

```text
README.md
01-inventario-proxmox.md
02-topologia-atual.md
03-riscos-encontrados.md
04-plano-implementacao.md
05-plano-rollback.md
06-validacao-pre-implementacao.md
07-validacao-pos-implementacao.md
08-reverse-proxy.md
09-firewall.md
10-backup-e-restore.md
11-observabilidade-roadmap.md
12-cicd-roadmap.md
CHANGELOG.md
```

Também gerar, quando aplicável:

```text
configs/
  nginx/
    before/
    after/
  caddy/
  systemd/
  firewall/
scripts/
  inventory.sh
  precheck.sh
  healthcheck.sh
  rollback.sh
  postcheck.sh
```

### 6.1 Rastreabilidade app e-SUS PEC

Os requisitos abaixo vêm de `appEsusPEC.md` e devem ser cobertos pelos
entregáveis desta Spec:

```text
APP-REQ-001 -> tratar Debian 13 como contexto inicial do app.
APP-REQ-002 -> registrar risco do instalador Java sem DISPLAY/X11.
APP-REQ-003 -> priorizar instalação headless/console quando suportada.
APP-REQ-004 -> inventariar PostgreSQL, psql e pg_restore.
APP-REQ-005 -> classificar backup com file antes de usar pg_restore/psql.
APP-REQ-006 -> impedir vazamento de senha PostgreSQL em logs/histórico.
APP-REQ-007 -> exigir aprovação para parada de app e restore destrutivo.
APP-REQ-008 -> inventariar banco e mídias/galeria antes de restore.
APP-REQ-009 -> inventariar disco, partições e filesystem antes de expansão.
APP-REQ-010 -> preferir swapfile como alternativa segura quando partição swap
bloquear expansão e reparticionamento for arriscado.
```

Esses itens devem aparecer em `01-inventario-proxmox.md`,
`03-riscos-encontrados.md`, `04-plano-implementacao.md`,
`05-plano-rollback.md`, `06-validacao-pre-implementacao.md` e, quando houver
mudança aprovada, `07-validacao-pos-implementacao.md`.

## 7. Fase 0 — Preparação segura

### 7.1 Criar diretório de trabalho

Executar somente comandos seguros:

```bash
mkdir -p /root/proxmox-app-platform-spec/{configs,scripts,logs}
chmod 700 /root/proxmox-app-platform-spec
```

### 7.2 Registrar contexto inicial

Criar `README.md` contendo:

```text
- data e hora;
- hostname;
- usuário executor;
- objetivo da intervenção;
- aviso de que nenhuma mudança destrutiva deve ser feita sem aprovação;
- resumo do ambiente conhecido.
```

### 7.3 Confirmar identidade do host

Executar:

```bash
hostnamectl
date
whoami
pwd
```

Registrar saída em:

```text
logs/00-host-context.txt
```

## 8. Fase 1 — Inventário somente leitura

Esta fase é obrigatoriamente **read-only**.

### 8.1 Inventário Proxmox

Executar:

```bash
pveversion -v
pvesh get /nodes
pvesh get /cluster/resources
qm list
pct list
pvesm status
```

Salvar em:

```text
logs/01-pveversion.txt
logs/01-nodes.txt
logs/01-cluster-resources.txt
logs/01-qm-list.txt
logs/01-pct-list.txt
logs/01-storage-status.txt
```

Documentar em:

```text
01-inventario-proxmox.md
```

### 8.2 Inventário de rede do node

Executar:

```bash
ip -br addr
ip route
ip rule
bridge link
cat /etc/network/interfaces
```

Salvar em:

```text
logs/02-ip-addr.txt
logs/02-ip-route.txt
logs/02-ip-rule.txt
logs/02-bridge-link.txt
logs/02-network-interfaces.txt
```

Documentar em:

```text
02-topologia-atual.md
```

### 8.3 Inventário de firewall

Executar:

```bash
pve-firewall status || true
cat /etc/pve/firewall/cluster.fw 2>/dev/null || true
find /etc/pve/firewall -type f -maxdepth 2 -print -exec sed -n '1,220p' {} \; 2>/dev/null || true
nft list ruleset 2>/dev/null || true
iptables-save 2>/dev/null || true
```

Salvar em:

```text
logs/03-pve-firewall-status.txt
logs/03-pve-firewall-configs.txt
logs/03-nft-ruleset.txt
logs/03-iptables-save.txt
```

Documentar em:

```text
09-firewall.md
```

### 8.4 Inventário dos CTs relevantes

Para os CTs `100`, `110` e `120`, executar:

```bash
pct config 100
pct config 110
pct config 120
```

Salvar em:

```text
logs/04-pct-config-100.txt
logs/04-pct-config-110.txt
logs/04-pct-config-120.txt
```

Coletar IPs, status e interfaces:

```bash
pct status 100
pct status 110
pct status 120
```

Se estiverem em execução, executar comandos internos não destrutivos:

```bash
pct exec 110 -- hostnamectl
pct exec 110 -- ip -br addr
pct exec 110 -- ss -lntup
pct exec 110 -- systemctl --type=service --state=running

pct exec 120 -- hostnamectl
pct exec 120 -- ip -br addr
pct exec 120 -- ss -lntup
pct exec 120 -- systemctl --type=service --state=running
```

Salvar em logs correspondentes.

### 8.5 Descobrir aplicação no CT 120

Sem alterar nada, descobrir:

```bash
pct exec 120 -- ps aux
pct exec 120 -- ss -lntup
pct exec 120 -- systemctl list-unit-files
pct exec 120 -- systemctl --type=service --state=running
pct exec 120 -- find /etc/systemd/system -maxdepth 1 -type f -name "*.service" -print
pct exec 120 -- find /opt /srv /var/www -maxdepth 3 -type f 2>/dev/null | head -200
```

Identificar:

```text
- porta interna da aplicação;
- protocolo HTTP/HTTPS;
- se usa systemd;
- se usa Docker/Podman;
- se usa banco local;
- se há variáveis de ambiente;
- se há arquivos .env;
- se há logs em arquivo ou journald.
```

Não exibir segredos no relatório. Apenas indicar existência e caminho mascarado.

Exemplo:

```text
Foi identificado arquivo de ambiente em /opt/app/.env, porém seu conteúdo não foi exibido.
```

### 8.6 Inventário específico do e-SUS PEC

Se a aplicação alvo for e-SUS PEC, executar somente comandos não destrutivos no
recurso confirmado como alvo (`CT 120`, VM `101`, ou outro):

```bash
java -version || true
psql --version || true
pg_restore --version || true
lsblk -f
df -hT
free -h
systemctl --type=service --state=running
ss -lntup
find /opt /srv /var/www /home -maxdepth 3 -type f 2>/dev/null | head -300
find /opt /srv /var/www /home -maxdepth 4 \( -iname "*.backup" -o -iname "*.sql" -o -iname "*.zip" -o -iname "*.tar.gz" \) 2>/dev/null | head -200
```

Identificar e documentar sem revelar segredos:

```text
- versão do Java;
- se existe instalador `.jar` do e-SUS PEC;
- se há modo `-console` documentado ou testável sem executar instalação;
- versão do PostgreSQL;
- comandos `psql` e `pg_restore` disponíveis;
- bancos existentes apenas por nome, sem dumps;
- arquivos de backup encontrados e seus caminhos;
- existência de arquivos `.env`, sem imprimir conteúdo;
- diretórios de mídia/galeria/anexos;
- tamanho do disco, filesystem, uso de swap e necessidade de expansão.
```

## 9. Fase 2 — Análise de riscos antes da implementação

Criar `03-riscos-encontrados.md` com uma tabela:

```text
| ID | Risco | Evidência | Impacto | Probabilidade | Severidade | Recomendação |
```

Avaliar no mínimo:

```text
- portas públicas abertas;
- Proxmox exposto;
- SSH exposto;
- aplicação exposta diretamente;
- banco exposto;
- ausência de firewall;
- ausência de backup;
- ausência de health check;
- ausência de TLS;
- configuração frágil do nginx;
- logs insuficientes;
- falta de documentação;
- ausência de rollback;
- CT privilegiado, se existir;
- mount points sensíveis;
- uso inseguro de Docker em LXC, se existir.
- restauração de e-SUS PEC sem backup validado;
- senha de PostgreSQL exposta em histórico, logs ou documentação;
- backup `.backup` restaurado com ferramenta incorreta;
- dependência de GUI/Wayland/X11 para instalação em servidor;
- partição de swap bloqueando expansão de disco;
- alteração de partição ou `/etc/fstab` sem janela de manutenção.
```

Parar após esta fase e apresentar resumo.

## 10. Fase 3 — Proposta de arquitetura alvo

Criar `04-plano-implementacao.md` com a arquitetura alvo:

```text
Internet
  |
Roteador/firewall público
  |
Port-forward apenas 80/443
  |
CT 110 - Reverse Proxy
  |
Rede privada Proxmox
  |
CT 120 - Aplicação
```

### 10.1 Decisão sobre reverse proxy

Preferência inicial:

```text
- Manter nginx se já estiver instalado e funcional.
- Não migrar para Caddy ou Traefik sem autorização separada.
- Usar nginx como ponto de entrada inicial.
```

### 10.2 Regras esperadas

```text
- CT 120 aceita tráfego HTTP apenas do CT 110.
- CT 120 não recebe tráfego público direto.
- CT 110 escuta 80/443.
- Administração do CT 110 e CT 120 apenas por VPN/NetBird ou rede administrativa.
- Proxmox 8006 não deve ser publicado.
```

### 10.3 Variáveis que devem ser confirmadas antes de implementar

Gerar uma seção “Pendências de confirmação”:

```text
- domínio público da aplicação;
- IP interno do CT 110;
- IP interno do CT 120;
- porta interna da aplicação no CT 120;
- se o alvo real é o CT 120 ou a VM 101 ESUS-TESTE;
- versão do e-SUS PEC;
- caminho de instalação do e-SUS PEC;
- serviço real da aplicação (`esus`, `wildfly`, `tomcat` ou outro);
- versão e modo de autenticação do PostgreSQL;
- caminho e formato do backup (`.backup`, `.sql`, `.zip`, `.tar.gz`);
- se há mídias/galeria/anexos no backup;
- necessidade real de expansão de disco e tamanho de swap desejado;
- se TLS será finalizado no nginx;
- se haverá certificado Let's Encrypt, certificado próprio ou HTTP temporário;
- janela de manutenção;
- autorização para reload do nginx;
- autorização para snapshot/backup;
- autorização para alteração de firewall.
```

Não avançar para aplicação de mudanças se essas variáveis não forem conhecidas.

## 11. Fase 4 — Backup e rollback antes de qualquer mudança

Antes de alterar nginx, firewall ou serviço, executar backup da configuração.

### 11.1 Snapshot ou backup Proxmox

Verificar se é possível criar snapshot dos CTs:

```bash
pct snapshot 110 pre-reverse-proxy-$(date +%Y%m%d-%H%M%S)
pct snapshot 120 pre-app-publish-$(date +%Y%m%d-%H%M%S)
```

Se snapshot não for possível, documentar motivo e propor alternativa.

### 11.2 Backup de configuração do nginx

No CT `110`:

```bash
pct exec 110 -- mkdir -p /root/backup-pre-change/nginx-$(date +%Y%m%d-%H%M%S)
pct exec 110 -- sh -c 'cp -a /etc/nginx /root/backup-pre-change/nginx-$(date +%Y%m%d-%H%M%S)/'
```

Também copiar para o diretório da Spec no host, se viável:

```bash
mkdir -p /root/proxmox-app-platform-spec/configs/nginx/before
pct pull 110 /etc/nginx/nginx.conf /root/proxmox-app-platform-spec/configs/nginx/before/nginx.conf || true
```

### 11.3 Plano de rollback obrigatório

Criar `05-plano-rollback.md` contendo:

```text
- como restaurar config anterior do nginx;
- como testar nginx após restauração;
- como fazer reload seguro;
- como voltar snapshot do CT 110;
- como voltar snapshot do CT 120;
- quais comandos não devem ser executados sem confirmação;
- impacto esperado do rollback.
```

Exemplo de rollback nginx:

```bash
nginx -t
systemctl reload nginx
```

Se `nginx -t` falhar, não fazer reload.

## 12. Fase 5 — Validação pré-implementação

Criar e executar `scripts/precheck.sh`.

O script deve coletar:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "== Host =="
hostnamectl || true
date || true

echo "== Proxmox CTs =="
pct list || true

echo "== Rede host =="
ip -br addr || true
ip route || true

echo "== CT 110 nginx status =="
pct status 110 || true
pct exec 110 -- systemctl status nginx --no-pager || true
pct exec 110 -- nginx -t || true
pct exec 110 -- ss -lntup || true

echo "== CT 120 app status =="
pct status 120 || true
pct exec 120 -- ss -lntup || true
pct exec 120 -- systemctl --type=service --state=running || true
```

Salvar saída em:

```text
logs/06-precheck-output.txt
```

Criar `06-validacao-pre-implementacao.md` com:

```text
- status dos CTs;
- IPs detectados;
- porta detectada da aplicação;
- status do nginx;
- resultado de nginx -t;
- serviços ativos;
- risco de indisponibilidade;
- decisão: apto ou não apto para implementação.
```

Não implementar se:

```text
- nginx -t falhar;
- CT 110 estiver instável;
- CT 120 estiver instável;
- porta da aplicação não for identificada;
- não houver rollback;
- houver dúvida sobre domínio, IP ou porta.
```

## 13. Fase 6 — Implementação do reverse proxy

Somente executar após aprovação explícita.

### 13.1 Modelo nginx esperado

Gerar arquivo de configuração proposto em:

```text
configs/nginx/after/app.conf
```

Modelo:

```nginx
server {
    listen 80;
    server_name app.exemplo.gov.br;

    access_log /var/log/nginx/app.access.log;
    error_log  /var/log/nginx/app.error.log;

    location / {
        proxy_pass http://IP_INTERNO_CT_120:PORTA_APP;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /healthz-proxy {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
```

Substituir:

```text
app.exemplo.gov.br
IP_INTERNO_CT_120
PORTA_APP
```

pelos valores reais, previamente confirmados.

### 13.2 Instalação da configuração

No CT `110`:

```bash
pct push 110 /root/proxmox-app-platform-spec/configs/nginx/after/app.conf /etc/nginx/sites-available/app.conf
pct exec 110 -- ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf
pct exec 110 -- nginx -t
```

Somente se `nginx -t` passar:

```bash
pct exec 110 -- systemctl reload nginx
```

Registrar tudo em:

```text
logs/07-nginx-implementation.txt
```

### 13.3 TLS

Nesta fase, não instalar certificado automaticamente sem autorização.

Documentar opções:

```text
Opção A: HTTP temporário para teste interno.
Opção B: Certificado Let's Encrypt com HTTP-01, se domínio público apontar corretamente.
Opção C: Certificado wildcard/importado.
Opção D: TLS somente no proxy de borda externo, se existir.
```

Se autorizado Let's Encrypt, antes validar:

```text
- domínio resolve para IP público correto;
- porta 80 está acessível externamente;
- não há bloqueio do provedor;
- nginx responde ao server_name.
```

## 14. Fase 7 — Firewall

Não aplicar regras sem aprovação.

### 14.1 Política alvo

Documentar:

```text
Entrada pública:
- permitir 80/tcp e 443/tcp somente para CT 110/reverse proxy.

Administração:
- permitir Proxmox 8006 somente pela rede administrativa/VPN.
- permitir SSH somente pela rede administrativa/VPN.

Aplicação:
- permitir acesso ao CT 120 somente a partir do CT 110 na porta da aplicação.
- negar acesso direto externo ao CT 120.

Banco:
- permitir acesso ao banco apenas a partir da aplicação e rotinas de backup.
```

### 14.2 Validação antes de firewall

Antes de aplicar qualquer regra, registrar:

```bash
pve-firewall status
nft list ruleset
iptables-save
```

### 14.3 Aplicação gradual

Aplicar regras em modo controlado:

```text
1. Criar regras, mas não ativar default drop global sem janela.
2. Testar conectividade local.
3. Testar acesso por VPN/NetBird.
4. Testar aplicação via reverse proxy.
5. Só então endurecer política.
```

### 14.4 Condição de bloqueio

Não aplicar firewall se:

```text
- não houver acesso alternativo ao node;
- NetBird não estiver funcional;
- não houver console físico/iDRAC/IPMI/out-of-band;
- não houver rollback claro;
- houver risco de lockout administrativo.
```

## 15. Fase 8 — Health checks

Criar `scripts/healthcheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_HOST="${APP_HOST:-app.exemplo.gov.br}"
APP_INTERNAL_URL="${APP_INTERNAL_URL:-http://IP_INTERNO_CT_120:PORTA_APP}"
PROXY_LOCAL_URL="${PROXY_LOCAL_URL:-http://127.0.0.1/healthz-proxy}"

echo "== CT 120 internal app =="
pct exec 120 -- curl -fsS "$APP_INTERNAL_URL" >/dev/null && echo "OK app interna" || echo "FAIL app interna"

echo "== CT 110 nginx config =="
pct exec 110 -- nginx -t

echo "== CT 110 local proxy health =="
pct exec 110 -- curl -fsS "$PROXY_LOCAL_URL" && echo "OK proxy local" || echo "FAIL proxy local"

echo "== Host resolves app =="
getent hosts "$APP_HOST" || true

echo "== External-style HTTP test from host =="
curl -I --max-time 10 "http://$APP_HOST" || true
```

Ajustar variáveis reais antes de usar.

Salvar resultados em:

```text
logs/08-healthcheck-output.txt
```

## 16. Fase 9 — Validação pós-implementação

Criar `07-validacao-pos-implementacao.md`.

Validar, ponto a ponto:

### 16.1 Validação do CT 120

```bash
pct status 120
pct exec 120 -- ss -lntup
pct exec 120 -- systemctl --type=service --state=running
pct exec 120 -- curl -I http://127.0.0.1:PORTA_APP || true
```

Resultado esperado:

```text
- CT em execução;
- aplicação ouvindo apenas em IP/porta esperados;
- serviço principal ativo;
- resposta HTTP local válida.
```

### 16.2 Validação do CT 110

```bash
pct status 110
pct exec 110 -- nginx -t
pct exec 110 -- systemctl status nginx --no-pager
pct exec 110 -- ss -lntup
```

Resultado esperado:

```text
- nginx ativo;
- nginx -t sem erro;
- portas 80/443 conforme esperado;
- app.conf carregado.
```

### 16.3 Validação proxy → aplicação

Do CT `110`:

```bash
pct exec 110 -- curl -I http://IP_INTERNO_CT_120:PORTA_APP
```

Resultado esperado:

```text
- HTTP 200, 301, 302, 401 ou resposta esperada da aplicação;
- sem timeout;
- sem connection refused.
```

### 16.4 Validação cliente → proxy

Do host Proxmox:

```bash
curl -I http://DOMINIO_DA_APLICACAO
```

De uma máquina externa:

```bash
curl -I http://DOMINIO_DA_APLICACAO
```

Resultado esperado:

```text
- resposta HTTP coerente;
- cabeçalhos vindos do nginx;
- sem exposição direta do CT 120.
```

### 16.5 Validação de logs

```bash
pct exec 110 -- tail -n 100 /var/log/nginx/app.access.log
pct exec 110 -- tail -n 100 /var/log/nginx/app.error.log
```

Resultado esperado:

```text
- access.log registra requisições;
- error.log sem erros críticos;
- upstream responde corretamente.
```

### 16.6 Validação de segurança

Executar do host:

```bash
nmap -Pn -sT -p 22,80,443,8006,PORTA_APP IP_CT_110 || true
nmap -Pn -sT -p 22,80,443,8006,PORTA_APP IP_CT_120 || true
```

Se `nmap` não estiver instalado, não instalar automaticamente; apenas registrar indisponibilidade e sugerir instalação.

Resultado esperado:

```text
- CT 110 expõe apenas portas necessárias;
- CT 120 não expõe aplicação publicamente fora do caminho esperado;
- Proxmox 8006 não aparece acessível publicamente.
```

## 17. Fase 10 — Documentação final

Atualizar os arquivos:

### `08-reverse-proxy.md`

Incluir:

```text
- domínio configurado;
- upstream configurado;
- caminho do arquivo nginx;
- comandos de teste;
- comandos de reload;
- logs relevantes;
- rollback.
```

### `09-firewall.md`

Incluir:

```text
- estado atual;
- regras existentes;
- regras propostas;
- regras aplicadas;
- riscos pendentes;
- recomendações futuras.
```

### `10-backup-e-restore.md`

Incluir:

```text
- snapshots criados;
- backups de configuração criados;
- como restaurar;
- como testar restore;
- pendências de backup da aplicação e banco.
```

### `11-observabilidade-roadmap.md`

Planejar fase futura:

```text
Fase 1:
- node_exporter no host;
- nginx exporter ou logs nginx;
- Prometheus;
- Grafana;
- alertas básicos.

Fase 2:
- Loki;
- Promtail ou Grafana Alloy;
- dashboards por aplicação;
- alertas por indisponibilidade;
- alertas de disco, CPU, memória, backup e certificado.

Fase 3:
- auditoria centralizada;
- retenção de logs;
- integração com incidentes.
```

### `12-cicd-roadmap.md`

Planejar fase futura:

```text
Opção leve:
- Gitea;
- Woodpecker CI;
- Ansible para deploy.

Opção completa:
- GitLab CE;
- GitLab Runner;
- Container Registry;
- SonarQube Community;
- Trivy;
- Gitleaks;
- deploy automatizado por Ansible.

Não implementar nesta primeira fase sem aprovação.
```

## 18. Critérios de aceite

A implementação será considerada concluída somente se todos os itens abaixo forem verdadeiros:

```text
[ ] Inventário do Proxmox gerado.
[ ] Topologia atual documentada.
[ ] CT 110 e CT 120 analisados.
[ ] Porta real da aplicação identificada.
[ ] Riscos documentados.
[ ] Backup/snapshot ou alternativa documentada.
[ ] Rollback documentado.
[ ] nginx testado com nginx -t antes do reload.
[ ] Reverse proxy configurado sem erro.
[ ] Aplicação responde via reverse proxy.
[ ] Logs do nginx registram acesso.
[ ] Acesso direto indevido ao CT 120 foi avaliado.
[ ] Proxmox 8006 não foi exposto por esta implementação.
[ ] Nenhuma alteração destrutiva foi feita sem aprovação.
[ ] Documentação final atualizada.
[ ] Pendências e próximos passos foram listados.
```

## 19. Relatório final obrigatório

Ao terminar, produzir um resumo executivo com:

```text
1. O que foi analisado.
2. O que foi alterado.
3. O que não foi alterado.
4. Evidências dos testes.
5. URLs/domínios testados.
6. Serviços impactados.
7. Riscos remanescentes.
8. Como reverter.
9. Próximas recomendações.
```

## 20. Parada obrigatória

Antes de aplicar qualquer alteração real, parar e solicitar autorização humana explícita com o seguinte formato:

```text
Plano pronto para implementação.

Alterações propostas:
- ...
- ...
- ...

Riscos:
- ...
- ...

Rollback:
- ...
- ...

Confirme explicitamente para prosseguir.
```

Não prosseguir sem confirmação.

---

## Prompt curto para iniciar no Codex CLI

Você pode iniciar assim:

```text
Leia integralmente a SPEC abaixo e execute apenas as fases 0, 1, 2 e 3 em modo read-only. Não aplique mudanças. Não reinicie serviços. Não altere firewall, rede, nginx, CTs ou VMs. Gere os arquivos de inventário, riscos e plano de implementação. Ao final, pare e apresente um relatório com as evidências e pendências de confirmação.
```

Depois de validar o inventário, aí sim você roda uma segunda tarefa autorizando a fase de implementação.
