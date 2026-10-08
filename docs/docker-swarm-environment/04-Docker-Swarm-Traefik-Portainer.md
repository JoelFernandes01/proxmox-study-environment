# 🐳 Doc 4 — Docker Swarm + Traefik + Portainer

> **Autor:** Joel Fernandes  
> **Data:** 01/10/2026  
> **Objetivo:** Instalar e configurar o Docker Engine, inicializar o Swarm, adicionar nós, e implantar Traefik (reverse proxy) e Portainer (gestão) em um cluster.  
> **Pré-requisito:** VMs Ubuntu já preparadas conforme o **[Doc 1 — Base Ubuntu para Docker Swarm](./03-Base-Ubuntu-Swarm.md)**.

---

## 📋 Sumário

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Instalação do Docker Engine + containerd](#3-instalação-do-docker-engine--containerd)
4. [Inicialização do Swarm](#4-inicialização-do-swarm)
5. [Adição de Managers e Workers](#5-adição-de-managers-e-workers)
6. [Redes Overlay e Volumes](#6-redes-overlay-e-volumes)
7. [Secrets e Configs](#7-secrets-e-configs)
8. [Deploy do Traefik](#8-deploy-do-traefik)
9. [Deploy do Portainer](#9-deploy-do-portainer)
10. [Validação Final](#10-validação-final)
11. [Extração de Comandos do Histórico](#11-extração-de-comandos-do-histórico)
12. [Referências](#12-referências)

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
- **SO:** Ubuntu 26.x LTS — mesmo SO em todos os nós
- **Base já configurada:** NTP (`chrony`), kernel ajustado, UFW com portas do Swarm, ferramentas essenciais, histórico com timestamp (ver **[Doc 1](./03-Base-Ubuntu-Swarm.md)**)
- **Rede:** IPs fixos ou DHCP reservado, comunicação nas portas:
  - `2377/tcp` — cluster management
  - `7946/tcp/udp` — node communication
  - `4789/udp` — overlay network
  - `80/tcp` e `443/tcp` — Traefik
  - `9000/tcp` — Portainer (opcional, se exposto)
- **DNS:** domínio apontando para o IP do manager (ex.: `*.nverse.local` ou domínio público)
- **Acesso:** usuário com `sudo` em todos os nós

---

## 3. Instalação do Docker Engine + containerd

> ⚠️ Rodar em **cada** nó do cluster (managers e workers).

### 3.1 Adicionar repositório oficial

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

### 3.2 Instalar Docker Engine, CLI e containerd

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3.3 Habilitar e validar

```bash
sudo systemctl enable --now docker
sudo systemctl status docker
docker --version
```

### 3.4 Permitir uso sem sudo (opcional)

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

---

## 4. Inicialização do Swarm

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

### 4.1 Guardar os tokens

```bash
docker swarm join-token worker    # token para workers
docker swarm join-token manager   # token para managers adicionais
```

> ⚠️ **Segurança:** trate esses tokens como segredos. Não commite no Git.

---

## 5. Adição de Managers e Workers

### 5.1 Adicionar managers adicionais (recomendado: 3 total)

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

### 5.2 Adicionar workers

Nos nós `docker-swarm-04`, `docker-swarm-05`, etc.:

```bash
docker swarm join --token <TOKEN_WORKER> <IP_MANAGER>:2377
```

### 5.3 Validar no manager

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

## 6. Redes Overlay e Volumes

### 6.1 Rede overlay para Traefik (pública)

```bash
docker network create --driver overlay --attachable traefik-public
```

### 6.2 Rede overlay interna (backend)

```bash
docker network create --driver overlay --attachable backend
```

### 6.3 Volumes persistentes

```bash
docker volume create traefik-certificates
docker volume create portainer-data
```

> 💡 Em produção, considere usar **NFS, Ceph, GlusterFS** ou **Longhorn** para volumes compartilhados entre nós.

---

## 7. Secrets e Configs

### 7.1 Criar secrets (via stdin ou arquivo)

```bash
echo "minha-senha-forte" | docker secret create portainer_admin_password -
docker secret create traefik_acme_json ./acme.json
```

### 7.2 Listar e inspecionar

```bash
docker secret ls
docker config ls
```

> ⚠️ **Nunca** use `docker secret create nome valor` em histórico de shell — o valor fica gravado. Sempre use `-` (stdin) ou arquivo.

---

## 8. Deploy do Traefik

### 8.1 Arquivo `traefik.yml` (config estática)

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

### 8.2 Stack `traefik.yml` (deploy)

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

### 8.3 Deploy

```bash
docker stack deploy -c traefik.yml traefik
docker stack services traefik
docker service logs traefik_traefik -f
```

---

## 9. Deploy do Portainer

### 9.1 Stack `portainer.yml`

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

### 9.2 Deploy

```bash
docker stack deploy -c portainer.yml portainer
docker stack services portainer
docker service logs portainer_portainer -f
```

### 9.3 Acesso

- Abrir `https://portainer.nverse.local`
- Criar admin na primeira vez
- Selecionar "Agent" → `tasks.agent:9001`

---

## 10. Validação Final

### 10.1 Verificações essenciais

```bash
docker node ls                     # nós do cluster
docker stack ls                    # stacks implantadas
docker service ls                  # serviços ativos
docker network ls                  # redes (incluindo overlay)
docker volume ls                   # volumes
docker secret ls                   # secrets
```

### 10.2 Teste funcional

```bash
# Deploy de um serviço de teste
docker service create --name teste --replicas 2 --network traefik-public nginx:alpine
docker service ps teste
docker service logs teste
docker service rm teste
```

### 10.3 Verificar Traefik e Portainer

```bash
curl -I https://traefik.nverse.local
curl -I https://portainer.nverse.local
```

---

## 11. Extração de Comandos do Histórico

> 💡 **Lembrete:** o timestamp (`HISTTIMEFORMAT`) já foi configurado no **[Doc 1 — Seção 7](./03-Base-Ubuntu-Swarm.md#7-timestamp-no-histórico-do-bash)**.

### 11.1 Garantir que o histórico está salvo em disco

```bash
history -w
wc -l ~/.bash_history
```

### 11.2 Salvar snapshot final do histórico

```bash
cp ~/.bash_history ~/bash-history-fim-$(date +%Y%m%d-%H%M).txt
```

### 11.3 Comparar início vs fim (o que mudou)

```bash
diff ~/bash-history-inicio-*.txt ~/bash-history-fim-*.txt
```

> 💡 Isso mostra **exatamente** os comandos que você rodou durante a montagem do ambiente — ouro puro para a documentação.

### 11.4 Filtros por categoria

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

**Catch-all (tudo relacionado a Docker):**

```bash
grep -iE "(docker|containerd|swarm|traefik|portainer)" ~/.bash_history | sort -u
```

### 11.5 Gerar arquivo estruturado

```bash
{
  echo "# Comandos — Docker Swarm"
  grep -E "docker swarm|docker node" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Traefik"
  grep -iE "(traefik|traefik\.yml|traefik\.toml|acme\.json)" ~/.bash_history | sort -u
  echo ""
  echo "# Comandos — Portainer"
  grep -iE "(portainer|portainer-agent)" ~/.bash_history | sort -u
} > ~/comandos-swarm-completo.txt
```

### 11.6 ⚠️ Atenção ao `sudo` e sessões separadas

- Comandos com `sudo` na **mesma sessão do usuário** vão para `~/.bash_history`
- Se você virou **root** com `sudo -i` ou `su`, os comandos vão para `/root/.bash_history`
- Para juntar os dois históricos:

```bash
sudo cat /root/.bash_history >> ~/comandos-swarm-completo.txt
sort -u ~/comandos-swarm-completo.txt -o ~/comandos-swarm-completo.txt
```

---


## 12. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **04-Docker-Swarm-Traefik-Portainer.md** *(este documento)* | Instalação do Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL multi-disco |
| **[09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md)** | MariaDB multi-disco |
| **[10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md)** | Servidor NFS para persistência |

---

## 13. Referências Externas

- [Docker Swarm — Documentação oficial](https://docs.docker.com/engine/swarm/)
- [Traefik v3 — Documentação oficial](https://doc.traefik.io/traefik/)
- [Portainer — Documentação oficial](https://docs.portainer.io/)
- [Docker Engine — Instalação no Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Let's Encrypt — ACME Challenge](https://letsencrypt.org/docs/challenge-types/)

---

## 🧠 Lições Aprendidas

1. **`history -w`** antes de extrair — o histórico em memória pode não estar no disco ainda.
2. **`sudo -i`** cria histórico separado em `/root/.bash_history`.
3. **Nunca commite `acme.json`** — contém chaves privadas TLS.
4. **Nunca commite tokens do Swarm** (`SWMTKN-*`) — quem tiver o token entra no cluster.
5. **`docker secret create` via stdin** (`-`) evita que o valor fique no histórico do shell.
6. **Sempre valide** com `docker node ls`, `docker stack ls`, `docker service ls` após cada etapa.

---

*Documento gerado em 01/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
