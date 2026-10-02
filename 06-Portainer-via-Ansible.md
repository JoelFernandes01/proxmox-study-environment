# 🐳 Doc 6 — Portainer via Ansible

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar a configuração do Portainer no cluster Docker Swarm, incluindo deploy via Ansible, setup inicial, integração com Traefik e troubleshooting.  
> **Pré-requisito:** Cluster Swarm configurado (Doc 5), Traefik v2.11 deployado, Docker 29.x.

---

## 📋 Sumário

1. [Visão Geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Estrutura de Arquivos](#3-estrutura-de-arquivos)
4. [Template do Portainer](#4-template-do-portainer)
5. [Playbook de Deploy](#5-playbook-de-deploy)
6. [Setup Inicial](#6-setup-inicial)
7. [Integração com Traefik](#7-integração-com-traefik)
8. [Troubleshooting](#8-troubleshooting)
9. [Referências Cruzadas](#9-referências-cruzadas)

---

## 1. Visão Geral

O **Portainer** é uma interface web para gerenciar clusters Docker Swarm e Kubernetes. No nosso ambiente, ele roda como uma stack no Swarm, com:

- ✅ **Agent** em todos os 6 nós (`mode: global`)
- ✅ **Server** no manager 01 (`mode: replicated`, replicas: 1)
- ✅ **Acesso via Traefik** (labels)
- ✅ **Volume persistente** (`portainer-data`)

### Arquitetura

```
┌─────────────────────────────────────────────────────┐
│  Cliente (navegador)                                │
│         ↓ http://portainer.nverse.local             │
├─────────────────────────────────────────────────────┤
│  Traefik (manager 01/02/03)                         │
│         ↓ lê labels do serviço                      │
├─────────────────────────────────────────────────────┤
│  portainer_portainer (manager 01)                   │
│         ↓ conecta no agent                          │
├─────────────────────────────────────────────────────┤
│  portainer_agent (6 nós)                            │
│         ↓ gerencia o Docker local                   │
└─────────────────────────────────────────────────────┘
```

---

## 2. Pré-requisitos

- **Cluster Swarm** funcional (Doc 5)
- **Traefik** deployado e funcionando
- **Redes overlay**: `traefik-public`, `backend`
- **Volume**: `portainer-data`
- **DNS**: `portainer.nverse.local` apontando para o manager

---

## 3. Estrutura de Arquivos

```
ansible/
└── playbooks/
    ├── 05-deploy-stacks.yml       ← Playbook (Traefik + Portainer)
    ├── group_vars/
    │   └── all.yml                ← Variáveis
    └── templates/
        └── portainer.yml.j2       ← Template do Portainer
```

---

## 4. Template do Portainer

**Arquivo:** `ansible/playbooks/templates/portainer.yml.j2`

```yaml
version: "3.8"

services:
  agent:
    image: portainer/agent:{{ portainer_version }}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - backend
    deploy:
      mode: global

  portainer:
    image: portainer/portainer-ce:{{ portainer_version }}
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
        - "traefik.http.routers.portainer.rule=Host(`{{ portainer_domain }}`)"
        - "traefik.http.routers.portainer.entrypoints=web"
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

### Variáveis utilizadas

**Arquivo:** `ansible/playbooks/group_vars/all.yml`

```yaml
portainer_version: "latest"
portainer_domain: "portainer.nverse.local"
```

---

## 5. Playbook de Deploy

**Arquivo:** `ansible/playbooks/05-deploy-stacks.yml` (trecho do Portainer)

```yaml
- name: Deploy Portainer
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Copiar stack do Portainer
      copy:
        dest: /tmp/portainer.yml
        content: "{{ lookup('template', 'portainer.yml.j2') }}"

    - name: Deploy da stack Portainer
      command: docker stack deploy -c /tmp/portainer.yml portainer
```

### Execução

```bash
cd ansible/
ansible-playbook playbooks/05-deploy-stacks.yml
```

### Validação

```bash
ssh connect@10.0.39.100 "docker service ls | grep portainer"
```

**Esperado:**

```
y95w6txzommo   portainer_agent       global       6/6        portainer/agent:latest
xmrtfg66ay4a   portainer_portainer   replicated   1/1        portainer/portainer-ce:latest
```

---

## 6. Setup Inicial

### 6.1 Acessar o Portainer

Abra no navegador:

```
http://portainer.nverse.local
```

### 6.2 Pegar o Setup Token

O Portainer exige um **setup token** na primeira execução (segurança). Pegue nos logs:

```bash
ssh connect@10.0.39.100 "docker service logs portainer_portainer 2>&1 | grep -o 'setup_token=[0-9a-f]*' | tail -1"
```

> ⚠️ **O token só é válido por 5 minutos.** Se expirar, reinicie o serviço:
> ```bash
> ssh connect@10.0.39.100 "docker service update --force portainer_portainer"
> ```

### 6.3 Criar Admin

1. Cole o **setup token**
2. Defina **username** (`admin`) e **password** (mínimo 12 caracteres)
3. Clique em **Create user**

### 6.4 Pular Edge Compute

Na tela **"Set up Edge Compute"**, clique em **Skip** (você não tem dispositivos Edge).

### 6.5 Conectar ao Cluster Swarm

No **Environment Wizard**:

| Campo | Valor |
|-------|-------|
| **Environment type** | Docker Swarm |
| **Connection** | Agent |
| **Name** | `docker-swarm` |
| **Agent URL** | `tasks.agent:9001` |

Clique em **Connect**. 🎉

---

## 7. Integração com Traefik

### 7.1 Como Funciona

O Traefik lê **labels** dos serviços do Swarm para criar rotas. O Portainer declara:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.portainer.rule=Host(`portainer.nverse.local`)"
  - "traefik.http.routers.portainer.entrypoints=web"
  - "traefik.http.services.portainer.loadbalancer.server.port=9000"
  - "traefik.docker.network=traefik-public"
```

| Label | Função |
|-------|--------|
| `traefik.enable=true` | Habilita o roteamento |
| `traefik.http.routers.portainer.rule=Host(...)` | Regra de host |
| `traefik.http.routers.portainer.entrypoints=web` | Entrypoint (porta 80) |
| `traefik.http.services.portainer.loadbalancer.server.port=9000` | Porta interna |
| `traefik.docker.network=traefik-public` | Rede do Traefik |

### 7.2 Testar

```bash
curl -sI http://portainer.nverse.local 2>&1 | head -5
```

**Esperado:**

```
HTTP/1.1 200 OK
```

ou

```
HTTP/1.1 302 Found
```

---

## 8. Troubleshooting

### 8.1 Setup Token Inválido

**Sintoma**: `Request failed with status code 403` ao criar admin.

**Causa**: Token expirado (janela de 5 minutos) ou token antigo (de reinicialização anterior).

**Solução**:

```bash
# 1. Reiniciar o Portainer (gera novo token)
ssh connect@10.0.39.100 "docker service update --force portainer_portainer"

# 2. Aguardar 5s e pegar o token novo
sleep 5
ssh connect@10.0.39.100 "docker service logs portainer_portainer 2>&1 | grep -o 'setup_token=[0-9a-f]*' | tail -1"

# 3. Acessar em janela anônima IMEDIATAMENTE
```

> 🥇 **Sempre use o `tail -1` para pegar o token mais recente.**

### 8.2 Erro 403 Persistente

**Sintoma**: Mesmo com o token novo, erro 403 continua.

**Causa**: Volume `portainer-data` com dados corrompidos de tentativas anteriores.

**Solução**:

```bash
# 1. Remover a stack
ssh connect@10.0.39.100 "docker stack rm portainer"

# 2. Remover o volume (⚠️ apaga configuração)
ssh connect@10.0.39.100 "docker volume rm portainer-data"

# 3. Re-deployar
ansible-playbook playbooks/05-deploy-stacks.yml
```

### 8.3 Portainer Não Conecta ao Agent

**Sintoma**: `Unable to connect to the agent` no wizard.

**Causa**: Agent não está rodando ou URL errada.

**Solução**:

```bash
# Verificar o agent
ssh connect@10.0.39.100 "docker service ps portainer_agent --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"

# Testar DNS interno
ssh connect@10.0.39.100 "docker exec \$(docker ps -q -f name=portainer_portainer) getent hosts tasks.agent"
```

### 8.4 Traefik Retorna 404

**Sintoma**: `curl -sI http://portainer.nverse.local` retorna 404.

**Causa**: Labels não estão sendo lidas pelo Traefik.

**Solução**:

```bash
# Verificar labels do serviço
ssh connect@10.0.39.100 "docker service inspect portainer_portainer --format '{{json .Spec.TaskTemplate.ContainerSpec.Labels}}' | jq"

# Verificar logs do Traefik
ssh connect@10.0.39.100 "docker service logs traefik_traefik --tail 20 | grep -iE 'error|portainer'"
```

### 8.5 Portainer Timeout

**Sintoma**: `Location: /timeout.html` ao acessar.

**Causa**: Portainer expirou por segurança (sem admin criado).

**Solução**:

```bash
ssh connect@10.0.39.100 "docker service update --force portainer_portainer"
```

E acesse imediatamente para criar o admin.

---

## 9. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Swarm |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore` |
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Playbooks Ansible |
| **06-Portainer-via-Ansible.md** *(este documento)* | Portainer + Traefik |

---

## 🧠 Lições Aprendidas

1. **Setup token expira em 5 minutos** — sempre use `tail -1` para pegar o mais recente.
2. **Erro 403 persistente = volume corrompido** — remova o `portainer-data` e recrie.
3. **Use janela anônima** para o setup inicial (evita cache/cookies).
4. **Agent URL é `tasks.agent:9001`** — `tasks.` resolve para qualquer réplica.
5. **Volume `portainer-data` é crítico** — contém toda a configuração.
6. **Labels do Traefik** são lidas em tempo real pelo provider swarm.
7. **Pule o Edge Compute** se não tiver dispositivos remotos.
8. **DNS correto** é essencial — `/etc/hosts` tem prioridade.

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
