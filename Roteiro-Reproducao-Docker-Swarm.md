# 🐳 Roteiro de Reprodução — Ambiente Docker Swarm + Traefik + Portainer

> **Autor:** Joel Fernandes  
> **Data:** 01/10/2026  
> **Objetivo:** Documentação passo a passo para provisionar um ambiente Docker Swarm do zero, com Traefik (reverse proxy) e Portainer (gestão), incluindo boas práticas de extração de histórico e governança.

---

## 📋 Sumário

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Preparação do Host (todos os nós)](#3-preparação-do-host-todos-os-nós)
4. [Instalação do Docker Engine + containerd](#4-instalação-do-docker-engine--containerd)
5. [Inicialização do Swarm](#5-inicialização-do-swarm)
6. [Adição de Workers](#6-adição-de-workers)
7. [Redes Overlay e Volumes](#7-redes-overlay-e-volumes)
8. [Secrets e Configs](#8-secrets-e-configs)
9. [Deploy do Traefik](#9-deploy-do-traefik)
10. [Deploy do Portainer](#10-deploy-do-portainer)
11. [Validação Final](#11-validação-final)
12. [Extração de Comandos do Histórico (para documentação)](#12-extração-de-comandos-do-histórico-para-documentação)
13. [Checklist Pré-Push Git](#13-checklist-pré-push-git)
14. [Referências](#14-referências)

---

## 1. Visão Geral da Arquitetura

```
                 ┌──────────────────────────────┐
                 │       Internet / LAN         │
                 └──────────────┬───────────────┘
                                │
                    ┌───────────▼───────────┐
                    │      Traefik          │  ← Reverse Proxy + TLS (ACME)
                    │   (stack: traefik)    │
                    └───────────┬───────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
┌───────▼────────┐    ┌─────────▼─────────┐    ┌────────▼────────┐
│  Serviço A     │    │   Portainer       │    │   Serviço N     │
│ (app replicado)│    │ (gestão visual)   │    │                 │
└────────────────┘    └───────────────────┘    └─────────────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                        Swarm Overlay Network
                    (docker-swarm-01, 02, 03...)
```

| Componente | Papel |
|------------|-------|
| **Docker Engine** | Runtime dos containers |
| **Docker Swarm** | Orquestração (managers + workers) |
| **Traefik** | Reverse proxy, TLS automático (Let's Encrypt), roteamento por labels |
| **Portainer** | Interface web de gestão do cluster |
| **Overlay Network** | Comunicação entre serviços em nós diferentes |

---

## 2. Pré-requisitos

- **Hosts:** mínimo 3 VMs/servidores (ideal: 3 managers + N workers)
- **SO:** Ubuntu 22.04/24.04 LTS (ou Debian 12) — mesmo SO em todos os nós
- **Recursos por nó:** 2 vCPU, 4 GB RAM, 40 GB disco (mínimo)
- **Rede:** IPs fixos ou DHCP reservado, comunicação nas portas:
  - `2377/tcp` — cluster management
  - `7946/tcp/udp` — node communication
  - `4789/udp` — overlay network
  - `80/tcp` e `443/tcp` — Traefik
  - `9000/tcp` — Portainer (opcional, se exposto)
- **DNS:** domínio apontando para o IP do manager (ex.: `*.nverse.local` ou domínio público)
- **Acesso:** usuário com `sudo` em todos os nós

---

## 3. Preparação do Host (todos os nós)

> ⚠️ Rodar em **cada** nó do cluster (managers e workers).

### 3.1 Atualização do sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg lsb-release ca-certificates apt-transport-https software-properties-common
```

### 3.2 Configuração de hostname (opcional, recomendado)

```bash
sudo hostnamectl set-hostname docker-swarm-01
sudo reboot
```

### 3.3 Ajustes de kernel e swap (obrigatório para Kubernetes/Swarm)

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Módulos de kernel para overlay
cat <<EOF | sudo tee /etc/modules-load.d/docker.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Parâmetros de rede
cat <<EOF | sudo tee /etc/sysctl.d/99-docker.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 3.4 Firewall (UFW)

```bash
sudo ufw allow 22/tcp
sudo ufw allow 2377/tcp
sudo ufw allow 7946/tcp
sudo ufw allow 7946/udp
sudo ufw allow 4789/udp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## 4. Instalação do Docker Engine + containerd

### 4.1 Adicionar repositório oficial

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
```

### 4.2 Instalar Docker Engine, CLI e containerd

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 4.3 Habilitar e validar

```bash
sudo systemctl enable --now docker
sudo systemctl status docker
docker --version
```

### 4.4 Permitir uso sem sudo (opcional)

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

---

## 5. Inicialização do Swarm

> 🎯 Rodar **apenas no primeiro manager** (ex.: `docker-swarm-01`).

```bash
docker swarm init --advertise-addr <IP_DO_MANAGER>
```

**Saída esperada:**

```
Swarm initialized: current node (xxxxx) is now a manager.
To add a worker to this swarm, run the following command:
    docker swarm join --token SWMTKN-1-xxxxx <IP>:2377
To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

### 5.1 Guardar os tokens

```bash
docker swarm join-token worker    # token para workers
docker swarm join-token manager   # token para managers adicionais
```

> ⚠️ **Segurança:** trate esses tokens como segredos. Não commite no Git.

### 5.2 Adicionar managers adicionais (recomendado: 3 total)

Nos nós `docker-swarm-02` e `docker-swarm-03`:

```bash
docker swarm join --token <TOKEN_MANAGER> <IP_MANAGER>:2377
```

Depois, no manager principal, promover se necessário:

```bash
docker node promote docker-swarm-02
docker node promote docker-swarm-03
docker node ls
```

---

## 6. Adição de Workers

Nos nós `docker-swarm-04`, `docker-swarm-05`, etc.:

```bash
docker swarm join --token <TOKEN_WORKER> <IP_MANAGER>:2377
```

Validar no manager:

```bash
docker node ls
```

**Saída esperada:**

```
ID       HOSTNAME           STATUS   AVAILABILITY   MANAGER STATUS
xxxxx *  docker-swarm-01    Ready    Active         Leader
xxxxx    docker-swarm-02    Ready    Active         Reachable
xxxxx    docker-swarm-03    Ready    Active         Reachable
xxxxx    docker-swarm-04    Ready    Active
```

---

## 7. Redes Overlay e Volumes

### 7.1 Rede overlay para Traefik (pública)

```bash
docker network create --driver overlay --attachable traefik-public
```

### 7.2 Rede overlay interna (backend)

```bash
docker network create --driver overlay --attachable backend
```

### 7.3 Volumes persistentes (opcional, se usar volume driver local)

```bash
docker volume create traefik-certificates
docker volume create portainer-data
```

> 💡 Em produção, considere usar **NFS, Ceph, GlusterFS** ou **Longhorn** para volumes compartilhados entre nós.

---

## 8. Secrets e Configs

### 8.1 Criar secrets (a partir de arquivos locais)

```bash
echo "minha-senha-forte" | docker secret create portainer_admin_password -
docker secret create traefik_acme_json ./acme.json
```

### 8.2 Listar e inspecionar

```bash
docker secret ls
docker config ls
```

> ⚠️ **Nunca** use `docker secret create nome valor` em histórico de shell — o valor fica gravado. Sempre use `-` (stdin) ou arquivo.

---

## 9. Deploy do Traefik

### 9.1 Arquivo `traefik.yml` (config estática)

```yaml
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    swarmMode: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: seu-email@dominio.com
      storage: /acme.json
      httpChallenge:
        entryPoint: web
```

### 9.2 Stack `traefik.yml` (deploy)

```yaml
version: "3.8"

services:
  traefik:
    image: traefik:v3.0
    command:
      - --configFile=/etc/traefik/traefik.yml
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik-certificates:/acme.json
    networks:
      - traefik-public
    deploy:
      mode: global
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dashboard.rule=Host(`traefik.nverse.local`)"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.routers.dashboard.middlewares=auth"
        - "traefik.http.middlewares.auth.basicauth.users=admin:$$2y$$10$$..."
      update_config:
        order: start-first

volumes:
  traefik-certificates:
    external: true

networks:
  traefik-public:
    external: true
```

### 9.3 Deploy

```bash
docker stack deploy -c traefik.yml traefik
docker stack services traefik
docker service logs traefik_traefik -f
```

---

## 10. Deploy do Portainer

### 10.1 Stack `portainer.yml`

```yaml
version: "3.8"

services:
  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - backend
    deploy:
      mode: global

  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer-data:/data
    networks:
      - traefik-public
      - backend
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(`portainer.nverse.local`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=traefik-public"

volumes:
  portainer-data:
    external: true

networks:
  traefik-public:
    external: true
  backend:
    external: true
```

### 10.2 Deploy

```bash
docker stack deploy -c portainer.yml portainer
docker stack services portainer
docker service logs portainer_portainer -f
```

### 10.3 Acesso

- Abrir `https://portainer.nverse.local`
- Criar admin na primeira vez
- Selecionar "Agent" → `tasks.agent:9001`

---

## 11. Validação Final

### 11.1 Verificações essenciais

```bash
docker node ls                     # nós do cluster
docker stack ls                    # stacks implantadas
docker service ls                  # serviços ativos
docker network ls                  # redes (incluindo overlay)
docker volume ls                   # volumes
docker secret ls                   # secrets
```

### 11.2 Teste funcional

```bash
# Deploy de um serviço de teste
docker service create --name teste --replicas 2 --network traefik-public nginx:alpine
docker service ps teste
docker service logs teste
docker service rm teste
```

### 11.3 Verificar Traefik e Portainer

```bash
curl -I https://traefik.nverse.local
curl -I https://portainer.nverse.local
```

---

## 12. Extração de Comandos do Histórico (para documentação)

### 12.1 Configurar timestamp no histórico (IMPORTANTE)

Adicione ao `~/.bashrc` (ou `~/.zshrc`):

```bash
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=100000
export HISTFILESIZE=200000
```

Depois:

```bash
source ~/.bashrc
```

A partir de agora, todo comando terá **data/hora** no `history`, essencial para reconstruir a **ordem cronológica** dos passos.

### 12.2 Garantir que o histórico está salvo em disco

```bash
history -w
wc -l ~/.bash_history
```

### 12.3 Filtros por categoria

**Preparação do Host:**

```bash
grep -iE "(apt|apt-get|dpkg|curl|wget|gpg|chmod|usermod|systemctl|sysctl|ufw|modprobe).*(docker|containerd|swarm|overlay|br_netfilter)" ~/.bash_history | sort -u
```

**Docker Swarm:**

```bash
grep -E "docker swarm|docker node" ~/.bash_history | sort -u
```

**Traefik:**

```bash
grep -iE "(traefik|traefik\.yml|traefik\.toml|acme\.json)" ~/.bash_history | sort -u
```

**Portainer:**

```bash
grep -iE "(portainer|portainer-agent)" ~/.bash_history | sort -u
```

**Catch-all (tudo relacionado):**

```bash
grep -iE "(docker|containerd|swarm|traefik|portainer)" ~/.bash_history | sort -u
```

### 12.4 Gerar arquivo estruturado

```bash
{
  echo "# Comandos — Preparação do Host"
  grep -iE "(apt|apt-get|dpkg|curl|wget|gpg|chmod|usermod|systemctl|sysctl|ufw|modprobe).*(docker|containerd|swarm|overlay|br_netfilter)" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Docker Swarm"
  grep -E "docker swarm|docker node" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Traefik"
  grep -iE "(traefik|traefik\.yml|traefik\.toml|acme\.json)" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Portainer"
  grep -iE "(portainer|portainer-agent)" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Preparação Geral do Host"
  grep -iE "(sysctl|ufw|firewall|hostname|swapoff|modprobe|iptables)" ~/.bash_history | sort -u
} > ~/comandos-swarm-completo.txt
```

### 12.5 ⚠️ Atenção ao `sudo` e sessões separadas

- Comandos com `sudo` na **mesma sessão do usuário** vão para `~/.bash_history`
- Se você virou **root** com `sudo -i` ou `su`, os comandos vão para `/root/.bash_history`
- Para juntar os dois históricos:

```bash
sudo cat /root/.bash_history >> ~/comandos-swarm-completo.txt
sort -u ~/comandos-swarm-completo.txt -o ~/comandos-swarm-completo.txt
```

---

## 13. Checklist Pré-Push Git

> 🥇 **Nunca** dê push sem rodar esta sequência.

```bash
# 1. O que vai subir?
git status

# 2. Revisar staged linha a linha
git diff --cached

# 3. Quais commits vão?
git log origin/main..HEAD --oneline

# 4. Caçar segredos rastreados
git ls-files | grep -Ei "(secret|password|token|\.pem|\.key|tfstate|tfplan|\.env|acme\.json)"

# 5. Só então:
git push origin main
```

> Se o passo 4 retornar **qualquer coisa**, **PARE** e resolva antes de pushar.

### 13.1 `.gitignore` recomendado

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfstate.backup
*.tfplan
tfplan
crash.log

# Ansible
*.retry
.vault_pass
*.vault_pass

# Docker / Swarm
acme.json
*.pem
*.key
*.crt

# Segredos
.env
.env.*
!.env.example
secrets.tfvars
secrets.tfvars.json
*password*
*token*
*secret*

# Sistema
.DS_Store
Thumbs.db

# Editores
.vscode/
.idea/
*.swp
*.swo
```
---

## 14. Referências

- [Docker Swarm — Documentação oficial](https://docs.docker.com/engine/swarm/)
- [Traefik v3 — Documentação oficial](https://doc.traefik.io/traefik/)
- [Portainer — Documentação oficial](https://docs.portainer.io/)
- [Docker Engine — Instalação no Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Let's Encrypt — ACME Challenge](https://letsencrypt.org/docs/challenge-types/)

---

## 🧠 Lições Aprendidas (do processo real)

1. **Timestamp é ouro**: configure `HISTTIMEFORMAT` **antes** de começar a montar ambiente. Sem ele, você tem os comandos mas não a ordem exata.
2. **`history -w`** antes de extrair — o histórico em memória pode não estar no disco ainda.
3. **`sudo -i`** cria histórico separado em `/root/.bash_history`.
4. **Nunca commite `acme.json`** — contém chaves privadas TLS.
5. **Nunca commite tokens do Swarm** (`SWMTKN-*`) — quem tiver o token entra no cluster.
6. **`docker secret create` via stdin** (`-`) evita que o valor fique no histórico do shell.
7. **Sempre valide** com `docker node ls`, `docker stack ls`, `docker service ls` após cada etapa.

---

*Documento gerado em 01/10/2026 como roteiro oficial de reprodução do ambiente Docker Swarm da NVerse.*
