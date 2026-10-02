# 🤖 Doc 5 — Ansible para Docker Swarm

> **Autor:** Joel Fernandes  
> **Data:** 01/10/2026  
> **Objetivo:** Documentar a estrutura, os playbooks e a execução do Ansible para configurar o cluster Docker Swarm (3 managers + 3 workers), do zero ao deploy das stacks.  
> **Pré-requisito:** VMs criadas pelo Terraform (**[Doc 4](./01-Template-Proxmox-CloudInit.md)**), acesso SSH via chave, Ansible instalado no laptop.

---

## 📋 Sumário

1. [Por Que Ansible?](#1-por-que-ansible)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Estrutura de Pastas](#3-estrutura-de-pastas)
4. [Arquivo `ansible.cfg`](#4-arquivo-ansiblecfg)
5. [Inventory](#5-inventory)
6. [Variáveis Globais](#6-variáveis-globais)
7. [Playbook 1 — Base Ubuntu](#7-playbook-1--base-ubuntu)
8. [Playbook 2 — Instalar Docker](#8-playbook-2--instalar-docker)
9. [Playbook 3 — Swarm Init + Join](#9-playbook-3--swarm-init--join)
10. [Playbook 5 — Deploy das Stacks](#10-playbook-5--deploy-das-stacks)
11. [Templates](#11-templates)
12. [Execução](#12-execução)
13. [Troubleshooting](#13-troubleshooting)
14. [Referências Cruzadas](#14-referências-cruzadas)

---

## 1. Por Que Ansible?

| Terraform | Ansible |
|-----------|---------|
| Cria **infraestrutura** (VMs, redes, discos) | Configura **dentro** das VMs (pacotes, serviços, arquivos) |
| HCL | YAML |
| State-based | Task-based |
| Idempotente | Idempotente |
| "Quero 6 VMs" | "Quero Docker instalado nas 6" |

**A ordem é sempre:**

```
Terraform  →  Ansible  →  Aplicação
   ↓            ↓            ↓
 Cria VMs    Configura    Roda Docker
```

---

## 2. Pré-requisitos

- **VMs criadas** pelo Terraform (Doc 4)
- **Acesso SSH** funcionando com chave
- **Usuário `connect`** com `sudo` **sem senha**:
  ```bash
  # Na VM, verificar:
  sudo visudo
  # Deve ter: connect ALL=(ALL) NOPASSWD:ALL
  ```
- **Ansible instalado** no laptop:
  ```bash
  sudo apt update
  sudo apt install -y ansible
  ansible --version
  ```

---

## 3. Estrutura de Pastas

### 3.1 Criar a estrutura

```bash
mkdir -p ansible/{inventory,group_vars,playbooks,templates} && \
touch ansible/ansible.cfg \
      ansible/inventory/hosts.ini \
      ansible/group_vars/all.yml \
      ansible/playbooks/01-base-ubuntu.yml \
      ansible/playbooks/02-install-docker.yml \
      ansible/playbooks/03-swarm.yml \
      ansible/playbooks/05-deploy-stacks.yml \
      ansible/templates/traefik.yml.j2 \
      ansible/templates/portainer.yml.j2
```

### 3.2 Estrutura Final

```
ansible/
├── ansible.cfg
├── inventory/
│   └── hosts.ini
└── playbooks/
    ├── 01-base-ubuntu.yml
    ├── 02-install-docker.yml
    ├── 03-swarm.yml
    ├── 05-deploy-stacks.yml
    ├── group_vars/
    │   └── all.yml
    └── templates/
        ├── traefik.yml.j2
        └── portainer.yml.j2
```

> ⚠️ **Importante:** o `group_vars/` e o `templates/` **DEVEM** ficar dentro de `playbooks/`, não na raiz do `ansible/`. O Ansible procura esses diretórios **relativos ao playbook**.

### 3.3 Verificar

```bash
tree ansible/ 2>/dev/null || find ansible/ -type f | sort
```

---

## 4. Arquivo `ansible.cfg`

**Arquivo:** `ansible/ansible.cfg`

```ini
[defaults]
inventory = ./inventory/hosts.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = default
result_format = yaml
bin_ansible_callbacks = True
interpreter_python = auto_silent

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
```

> ⚠️ **`stdout_callback = default`** (não `yaml`). O callback `yaml` foi removido no `community.general 12.0.0`. Use `default` + `result_format = yaml`.

---

## 5. Inventory

**Arquivo:** `ansible/inventory/hosts.ini`

```ini
[managers]
docker-swarm-01 ansible_host=10.0.39.100
docker-swarm-02 ansible_host=10.0.39.101
docker-swarm-03 ansible_host=10.0.39.102

[workers]
docker-worker-01 ansible_host=10.0.39.120
docker-worker-02 ansible_host=10.0.39.121
docker-worker-03 ansible_host=10.0.39.122

[swarm:children]
managers
workers

[swarm:vars]
ansible_user=connect
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### Testar

```bash
cd ansible/
ansible all -m ping
```

**Esperado:** `pong` nos 6 hosts.

---

## 6. Variáveis Globais

**Arquivo:** `ansible/playbooks/group_vars/all.yml`

```yaml
---
swarm_network: "10.0.39.0/24"
swarm_gateway: "10.0.39.1"
swarm_manager_ip: "10.0.39.100"

ntp_servers:
  - a.st1.ntp.br
  - b.st1.ntp.br
  - pool.ntp.org

timezone: "America/Sao_Paulo"

swarm_ports_tcp:
  - 22
  - 2377
  - 7946
  - 80
  - 443

swarm_ports_udp:
  - 7946
  - 4789

docker_version: "latest"

traefik_version: "v2.11"
traefik_domain: "nverse.local"
traefik_email: "seu-email@dominio.com"

portainer_version: "latest"
portainer_domain: "portainer.nverse.local"
```

> ⚠️ **`traefik_version: "v2.11"`** — a v3 tem bug com Docker 29.x.

---

## 7. Playbook 1 — Base Ubuntu

**Arquivo:** `ansible/playbooks/01-base-ubuntu.yml`

```yaml
---
- name: Preparação base do Ubuntu para Docker Swarm
  hosts: swarm
  become: true
  gather_facts: true

  tasks:
    - name: Configurar fuso horário
      community.general.timezone:
        name: "{{ timezone }}"

    - name: Atualizar cache apt
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Atualizar pacotes
      apt:
        upgrade: dist
        autoremove: yes

    - name: Instalar chrony
      apt:
        name: chrony
        state: present

    - name: Configurar chrony
      copy:
        dest: /etc/chrony/chrony.conf
        content: |
          {% for server in ntp_servers %}
          pool {{ server }} iburst
          {% endfor %}
          driftfile /var/lib/chrony/chrony.drift
          rtcsync
          makestep 1 3
      notify: restart chrony

    - name: Habilitar chrony
      systemd:
        name: chrony
        enabled: yes
        state: started

    - name: Instalar ferramentas essenciais
      apt:
        name:
          - vim
          - nano
          - htop
          - ncdu
          - curl
          - wget
          - net-tools
          - dnsutils
          - traceroute
          - mtr-tiny
          - git
          - jq
          - yq
          - tree
          - unzip
          - bash-completion
        state: present

    - name: Desabilitar swap (runtime)
      command: swapoff -a
      changed_when: false

    - name: Desabilitar swap (fstab)
      replace:
        path: /etc/fstab
        regexp: '^([^#].*\sswap\s.*)$'
        replace: '# \1'

    - name: Carregar módulos de kernel
      modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - overlay
        - br_netfilter

    - name: Persistir módulos
      copy:
        dest: /etc/modules-load.d/docker.conf
        content: |
          overlay
          br_netfilter

    - name: Configurar sysctl
      copy:
        dest: /etc/sysctl.d/99-docker.conf
        content: |
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1
      notify: reload sysctl

    - name: Instalar UFW
      apt:
        name: ufw
        state: present

    - name: Regras UFW TCP
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop: "{{ swarm_ports_tcp }}"

    - name: Regras UFW UDP
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: udp
      loop: "{{ swarm_ports_udp }}"

    - name: Ativar UFW
      ufw:
        state: enabled
        policy: deny

    - name: Configurar HISTTIMEFORMAT
      blockinfile:
        path: /etc/bash.bashrc
        block: |
          export HISTTIMEFORMAT="%F %T "
          export HISTSIZE=100000
          export HISTFILESIZE=200000

  handlers:
    - name: restart chrony
      systemd:
        name: chrony
        state: restarted

    - name: reload sysctl
      command: sysctl --system
```

---

## 8. Playbook 2 — Instalar Docker

**Arquivo:** `ansible/playbooks/02-install-docker.yml`

```yaml
---
- name: Instalar Docker Engine em todos os nós
  hosts: swarm
  become: true
  gather_facts: true

  tasks:
    - name: Instalar dependências
      apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        state: present

    - name: Criar diretório keyrings
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Adicionar chave GPG do Docker
      shell: |
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
          gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      args:
        creates: /etc/apt/keyrings/docker.gpg

    - name: Ajustar permissões
      file:
        path: /etc/apt/keyrings/docker.gpg
        mode: '0644'

    - name: Adicionar repositório Docker
      apt_repository:
        repo: >-
          deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg]
          https://download.docker.com/linux/ubuntu
          {{ ansible_distribution_release }} stable
        state: present
        filename: docker

    - name: Atualizar cache apt
      apt:
        update_cache: yes

    - name: Instalar Docker
      apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-buildx-plugin
          - docker-compose-plugin
        state: present

    - name: Habilitar e iniciar Docker
      systemd:
        name: docker
        enabled: yes
        state: started

    - name: Adicionar usuário ao grupo docker
      user:
        name: "{{ ansible_user }}"
        groups: docker
        append: yes

    - name: Verificar versão
      command: docker --version
      register: docker_version_output
      changed_when: false

    - name: Mostrar versão
      debug:
        msg: "{{ docker_version_output.stdout }}"
```

---

## 9. Playbook 3 — Swarm Init + Join

**Arquivo:** `ansible/playbooks/03-swarm.yml`

> ⚠️ **Este playbook é UNIFICADO** (init + join). Separar em dois playbooks **NÃO funciona** porque o `set_fact` não persiste entre execuções.

```yaml
---
- name: Inicializar Docker Swarm no manager 01
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Verificar estado do Swarm
      command: docker info --format '{{ "{{" }}.Swarm.LocalNodeState{{ "}}" }}'
      register: swarm_state
      changed_when: false
      failed_when: false

    - name: Inicializar Swarm
      command: docker swarm init --advertise-addr {{ swarm_manager_ip }}
      when: swarm_state.stdout != "active"

    - name: Obter token worker
      command: docker swarm join-token -q worker
      register: worker_token
      changed_when: false

    - name: Obter token manager
      command: docker swarm join-token -q manager
      register: manager_token
      changed_when: false

    - name: Salvar tokens
      set_fact:
        swarm_worker_token: "{{ worker_token.stdout }}"
        swarm_manager_token: "{{ manager_token.stdout }}"

    - name: Mostrar tokens
      debug:
        msg:
          - "Worker token: {{ swarm_worker_token }}"
          - "Manager token: {{ swarm_manager_token }}"

- name: Adicionar managers adicionais
  hosts: managers[1:]
  become: true
  gather_facts: true

  tasks:
    - name: Verificar estado do Swarm
      command: docker info --format '{{ "{{" }}.Swarm.LocalNodeState{{ "}}" }}'
      register: swarm_state
      changed_when: false
      failed_when: false

    - name: Entrar como manager
      command: >
        docker swarm join
        --token {{ hostvars[groups['managers'][0]].swarm_manager_token }}
        {{ swarm_manager_ip }}:2377
      when: swarm_state.stdout != "active"

- name: Adicionar workers
  hosts: workers
  become: true
  gather_facts: true

  tasks:
    - name: Verificar estado do Swarm
      command: docker info --format '{{ "{{" }}.Swarm.LocalNodeState{{ "}}" }}'
      register: swarm_state
      changed_when: false
      failed_when: false

    - name: Entrar como worker
      command: >
        docker swarm join
        --token {{ hostvars[groups['managers'][0]].swarm_worker_token }}
        {{ swarm_manager_ip }}:2377
      when: swarm_state.stdout != "active"

- name: Validar cluster
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Listar nós
      command: docker node ls
      register: node_list
      changed_when: false

    - name: Mostrar nós
      debug:
        msg: "{{ node_list.stdout_lines }}"
```

---

## 10. Playbook 5 — Deploy das Stacks

**Arquivo:** `ansible/playbooks/05-deploy-stacks.yml`

```yaml
---
- name: Criar redes e volumes
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Criar rede traefik-public
      command: docker network create --driver overlay --attachable traefik-public
      register: net_traefik
      failed_when:
        - net_traefik.rc != 0
        - "'already exists' not in net_traefik.stderr"

    - name: Criar rede backend
      command: docker network create --driver overlay --attachable backend
      register: net_backend
      failed_when:
        - net_backend.rc != 0
        - "'already exists' not in net_backend.stderr"

    - name: Criar volume traefik-certificates
      command: docker volume create traefik-certificates
      register: vol_traefik
      failed_when:
        - vol_traefik.rc != 0
        - "'already exists' not in vol_traefik.stderr"

    - name: Criar volume portainer-data
      command: docker volume create portainer-data
      register: vol_portainer
      failed_when:
        - vol_portainer.rc != 0
        - "'already exists' not in vol_portainer.stderr"

- name: Deploy Traefik
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Copiar stack
      copy:
        dest: /tmp/traefik.yml
        content: "{{ lookup('template', 'traefik.yml.j2') }}"

    - name: Deploy
      command: docker stack deploy -c /tmp/traefik.yml traefik

- name: Deploy Portainer
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Copiar stack
      copy:
        dest: /tmp/portainer.yml
        content: "{{ lookup('template', 'portainer.yml.j2') }}"

    - name: Deploy
      command: docker stack deploy -c /tmp/portainer.yml portainer

- name: Validar stacks
  hosts: managers[0]
  become: true
  gather_facts: true

  tasks:
    - name: Listar stacks
      command: docker stack ls
      register: stack_list
      changed_when: false

    - name: Listar serviços
      command: docker service ls
      register: service_list
      changed_when: false

    - name: Mostrar resultado
      debug:
        msg:
          - "=== STACKS ==="
          - "{{ stack_list.stdout_lines }}"
          - "=== SERVICES ==="
          - "{{ service_list.stdout_lines }}"
```

---

## 11. Templates

### `ansible/playbooks/templates/traefik.yml.j2`

> ⚠️ **Traefik v2.11** (a v3 tem bug com Docker 29.x).

```yaml
version: "3.8"

services:
  traefik:
    image: traefik:{{ traefik_version }}
    command:
      - --api.dashboard=true
      - --api.insecure=false
      - --providers.docker=true
      - --providers.docker.swarmMode=true
      - --providers.docker.exposedByDefault=false
      - --providers.docker.network=traefik-public
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
    environment:
      - DOCKER_API_VERSION=1.56
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
        - "traefik.http.routers.dashboard.rule=Host(`traefik.{{ traefik_domain }}`)"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.services.dashboard.loadbalancer.server.port=8080"

volumes:
  traefik-certificates:
    external: true

networks:
  traefik-public:
    external: true
```

### `ansible/playbooks/templates/portainer.yml.j2`

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

---

## 12. Execução

### 12.1 Testar conectividade

```bash
cd ansible/
ansible all -m ping
```

### 12.2 Rodar os playbooks em ordem

```bash
ansible-playbook playbooks/01-base-ubuntu.yml
ansible-playbook playbooks/02-install-docker.yml
ansible-playbook playbooks/03-swarm.yml
ansible-playbook playbooks/05-deploy-stacks.yml
```

### 12.3 Validar o cluster

```bash
ssh connect@10.0.39.100 "docker node ls"
ssh connect@10.0.39.100 "docker stack ls"
ssh connect@10.0.39.100 "docker service ls"
```

---

## 13. Troubleshooting

### 13.1 `community.general.yaml` removido

**Sintoma:** erro `The 'community.general.yaml' callback plugin has been removed`.

**Causa:** o callback `yaml` foi removido no `community.general 12.0.0`.

**Solução:** use `default` + `result_format = yaml`:

```ini
stdout_callback = default
result_format = yaml
```

### 13.2 Variável `'X' is undefined`

**Sintoma:** erro `'timezone' is undefined` mesmo com `all.yml` preenchido.

**Causa:** `group_vars/` no diretório errado. O Ansible procura em `playbooks/group_vars/`, não em `ansible/group_vars/`.

**Solução:**

```bash
mv group_vars/ playbooks/
```

### 13.3 Template não encontrado

**Sintoma:** erro `the template file traefik.yml.j2 could not be found`.

**Causa:** `templates/` no diretório errado.

**Solução:**

```bash
mv templates/ playbooks/
```

### 13.4 `set_fact` não persiste entre playbooks

**Sintoma:** `'swarm_manager_token' is undefined` no playbook de join.

**Causa:** o `set_fact` do playbook de init só existe **naquela execução**.

**Solução:** unificar os playbooks de init + join em **um só** (`03-swarm.yml`).

### 13.5 Zsh: `no matches found: managers[0]`

**Sintoma:** erro no Zsh ao usar `managers[0]`.

**Causa:** o Zsh interpreta `[0]` como **glob pattern**.

**Solução:** use aspas simples:

```bash
ansible 'managers[0]' -m command -a "docker node ls" -b
```

### 13.6 `watch` via SSH: `ncurses: cannot initialize terminal type`

**Sintoma:** erro ao rodar `watch` via SSH.

**Causa:** o SSH não aloca TTY por padrão.

**Solução:** use `ssh -t` ou `watch -n 2 ssh ...` no laptop.

### 13.7 `command` não interpreta `;`

**Sintoma:** `bad flag syntax: ---;` ao usar `;` no módulo `command`.

**Causa:** o módulo `command` **não invoca shell**.

**Solução:** use o módulo `shell`:

```bash
ansible host -m shell -a "docker stack ls && docker service ls"
```

### 13.8 Traefik v3: `swarmMode` removido

**Sintoma:** Traefik em CrashLoopBackOff com `swarmMode option has been removed`.

**Causa:** no Traefik v3, a opção `--providers.docker.swarmMode=true` foi removida.

**Solução:** use o provider separado `swarm` (v3) **OU** volte para o Traefik v2.11 (recomendado).

### 13.9 Traefik: `client version 1.24 is too old`

**Sintoma:** Traefik não lê os serviços do Swarm (`client version 1.24 is too old`).

**Causa:** incompatibilidade entre Traefik (v3.5.6) e Docker 29.x (API 1.56).

**Solução:** use **Traefik v2.11**:

```yaml
traefik_version: "v2.11"
```

### 13.10 Traefik v2: `port is missing`

**Sintoma:** `service "traefik-traefik" error: port is missing`.

**Causa:** o Traefik tenta criar um serviço para si mesmo, mas falta a label de porta.

**Solução:** adicionar a label:

```yaml
- "traefik.http.services.dashboard.loadbalancer.server.port=8080"
```

---

## 14. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação manual do Docker + stacks |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore` |
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox |
| **05-Ansible-Docker-Swarm.md** *(este documento)* | Playbooks Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |

---

## 🧠 Lições Aprendidas

1. **Ansible é idempotente** — pode rodar 2x, não quebra.
2. **Ordem importa** — base → docker → swarm → stacks.
3. **`group_vars/` e `templates/` DEVEM ficar em `playbooks/`**.
4. **`set_fact` não persiste entre playbooks** — unifique init + join.
5. **Zsh com `[0]`** — use `'managers[0]'` (aspas simples).
6. **`command` não interpreta `;`** — use `shell` quando precisar.
7. **Traefik v3.5.6 tem bug** com Docker 29.x — use v2.11.
8. **`DOCKER_API_VERSION`** — setar via env var (mesmo que ignorada).
9. **Validar cada camada antes de avançar**.
10. **Ler o `PLAY RECAP`** (`failed=0` é o que importa).

---

*Documento gerado em 01/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
