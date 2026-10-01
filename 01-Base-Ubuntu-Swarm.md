# 🐧 Doc 1 — Base Ubuntu para Docker Swarm

> **Autor:** Joel Fernandes  
> **Data:** 01/10/2026  
> **Objetivo:** Preparar uma VM Ubuntu 26.x (provisionada via Terraform no Proxmox 9.x) para receber o Docker Swarm, incluindo configurações base, ajustes de kernel, firewall e ferramentas essenciais.

---

## 📋 Sumário

1. [Pré-requisitos](#1-pré-requisitos)
2. [Configurações Base do Sistema](#2-configurações-base-do-sistema)
3. [Configuração de NTP (chrony)](#3-configuração-de-ntp-chrony)
4. [Ferramentas Essenciais](#4-ferramentas-essenciais)
5. [Ajustes de Kernel para Swarm](#5-ajustes-de-kernel-para-swarm)
6. [Firewall (UFW)](#6-firewall-ufw)
7. [Timestamp no Histórico do Bash](#7-timestamp-no-histórico-do-bash)
8. [Validação Final da VM](#8-validação-final-da-vm)
9. [Automação com Ansible (opcional)](#9-automação-com-ansible-opcional)
10. [Próximos Passos](#10-próximos-passos)

---

## 1. Pré-requisitos

- **VM provisionada pelo Terraform** no Proxmox 9.x
- **Ubuntu 26.x LTS** instalado (Server, sem GUI)
- **Acesso SSH via chave** (já configurada pelo Terraform)
- **Usuário com `sudo`** (ex.: `joelfernandes`)
- **IP fixo** ou DHCP reservado
- **Conectividade** com a internet (para apt) e com os demais nós

> 💡 Todas as configurações abaixo devem ser aplicadas em **cada nó** do cluster (managers e workers). Em produção, prefira automatizar via Ansible (ver Seção 9).

---

## 2. Configurações Base do Sistema

### 2.1 Fuso horário

```bash
sudo timedatectl set-timezone America/Sao_Paulo
timedatectl
```

**Saída esperada:**

```
               Local time: ...
           Time zone: America/Sao_Paulo (-03, -0300)
```

### 2.2 Locale (idioma e codificação)

```bash
sudo apt update
sudo apt install -y locales
sudo locale-gen pt_BR.UTF-8 en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
```

> 💡 Manter `LANG=en_US.UTF-8` evita surpresas com logs e scripts. O `pt_BR` fica disponível para uso pontual.

### 2.3 Atualização completa do sistema

```bash
sudo apt update
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt autoremove -y
sudo apt autoclean
```

### 2.4 Hostname (identificação no cluster)

```bash
sudo hostnamectl set-hostname docker-swarm-01
```

> ⚠️ Após mudar, é recomendável **reiniciar** para que todos os serviços peguem o novo nome.

---

## 3. Configuração de NTP (chrony)

> 🎯 Usaremos **chrony** por ser mais robusto e preciso que o `systemd-timesyncd`, especialmente em ambientes de cluster onde a sincronia de tempo é crítica (TLS, tokens do Swarm, logs).

### 3.1 Instalação

```bash
sudo apt install -y chrony
```

### 3.2 Configuração (servidores brasileiros)

Edite `/etc/chrony/chrony.conf`:

```bash
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
sudo tee /etc/chrony/chrony.conf > /dev/null << 'EOF'
# Servidores NTP brasileiros (NIC.br)
pool a.st1.ntp.br iburst
pool b.st1.ntp.br iburst
pool c.st1.ntp.br iburst
pool d.st1.ntp.br iburst

# Fallback internacional
pool pool.ntp.org iburst

# Permitir sincronização de clientes da rede local (opcional)
# allow 10.0.39.0/24

# Drift file e stats
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF
```

> 💡 O `makestep 1 3` permite que o chrony ajuste o relógio bruscamente nos primeiros 3 ajustes — útil no boot.

### 3.3 Aplicar e validar

```bash
sudo systemctl restart chrony
sudo systemctl enable chrony
chronyc tracking
chronyc sources -v
```

**Saída esperada do `tracking`:**

```
Reference ID    : ...
Stratum         : 2
System time     : 0.000xxx seconds fast/slow of NTP time
Last offset     : +0.000xxx seconds
RMS offset      : 0.000xxx seconds
```

---

## 4. Ferramentas Essenciais

### 4.1 Instalação em lote

```bash
sudo apt install -y \
  vim nano \
  htop ncdu \
  curl wget \
  net-tools dnsutils traceroute mtr-tiny \
  git \
  jq yq \
  tree \
  unzip \
  bash-completion
```

### 4.2 Detalhamento

| Ferramenta | Para quê |
|------------|----------|
| `vim`, `nano` | Editores de texto |
| `htop` | Monitor de processos interativo |
| `ncdu` | Análise de uso de disco (interativo) |
| `curl`, `wget` | Downloads, testes HTTP |
| `net-tools` | `ifconfig`, `netstat` (legado, mas útil) |
| `dnsutils` | `dig`, `nslookup` |
| `traceroute`, `mtr-tiny` | Diagnóstico de rede |
| `git` | Versionamento |
| `jq`, `yq` | Parse de JSON/YAML (essenciais para Docker/Swarm) |
| `tree` | Visualização de diretórios |
| `unzip` | Descompactar arquivos |
| `bash-completion` | Autocomplete no Bash |

### 4.3 Ativar autocomplete no Bash

```bash
sudo tee -a /etc/bash.bashrc > /dev/null << 'EOF'

# Habilita autocomplete global
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
```

Teste (em um novo terminal):

```bash
source /etc/bash.bashrc
docker <TAB><TAB>   # (após instalar Docker, mostrará os subcomandos)
```

---

## 5. Ajustes de Kernel para Swarm

> ⚠️ **Obrigatório.** Sem isso, o Swarm pode ter problemas com overlay network e roteamento entre containers.

### 5.1 Desabilitar swap (permanente)

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
free -h
```

**Saída esperada:** linha `Swap:` com `0B` em todas as colunas.

### 5.2 Carregar módulos de kernel

```bash
sudo tee /etc/modules-load.d/docker.conf > /dev/null << 'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

lsmod | grep -E "overlay|br_netfilter"
```

### 5.3 Parâmetros de rede (sysctl)

```bash
sudo tee /etc/sysctl.d/99-docker.conf > /dev/null << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

**Validação:**

```bash
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
```

Ambos devem retornar `= 1`.

---

## 6. Firewall (UFW)

### 6.1 Instalação e regras base

```bash
sudo apt install -y ufw

# SSH
sudo ufw allow 22/tcp

# Docker Swarm
sudo ufw allow 2377/tcp        # cluster management
sudo ufw allow 7946/tcp        # node communication (TCP)
sudo ufw allow 7946/udp        # node communication (UDP)
sudo ufw allow 4789/udp        # overlay network (VXLAN)

# Aplicações (Traefik)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Portainer (opcional, se expor diretamente)
# sudo ufw allow 9000/tcp

sudo ufw enable
sudo ufw status verbose
```

> ⚠️ **Atenção com Docker + UFW:** o Docker manipula `iptables` diretamente e pode **ignorar** regras do UFW em portas publicadas. Para ambientes de produção, considere usar `ufw-docker` ou configurar `iptables` manualmente.

---

## 7. Timestamp no Histórico do Bash

> 🎯 **Fazer AGORA**, antes de começar a montar o Swarm. Sem isso, você perde a ordem cronológica dos comandos.

### 7.1 Configurar `HISTTIMEFORMAT`

```bash
sudo tee -a /etc/bash.bashrc > /dev/null << 'EOF'

# Histórico — timestamp e tamanho ampliado
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=100000
export HISTFILESIZE=200000
EOF

source /etc/bash.bashrc
```

> 💡 Colocando em `/etc/bash.bashrc`, vale para **todos os usuários** do sistema. Se preferir só para o seu usuário, use `~/.bashrc`.

### 7.2 Validar

```bash
history 5
```

**Saída esperada:** cada linha com data/hora no início:

```
  501  2026-10-01 09:15:32 ls -la
  502  2026-10-01 09:15:40 docker --version
```

### 7.3 Snapshot inicial do histórico

```bash
history -w
cp ~/.bash_history ~/bash-history-inicio-$(date +%Y%m%d-%H%M).txt
```

---

## 8. Validação Final da VM

### 8.1 Checklist

```bash
echo "=== Hostname ===" && hostnamectl
echo "=== Fuso ===" && timedatectl | grep "Time zone"
echo "=== NTP ===" && chronyc tracking | grep -E "Reference|Stratum|System time"
echo "=== Swap ===" && free -h | grep Swap
echo "=== Módulos ===" && lsmod | grep -E "overlay|br_netfilter"
echo "=== Sysctl ===" && sysctl net.ipv4.ip_forward
echo "=== Firewall ===" && sudo ufw status | head -20
echo "=== Ferramentas ===" && for cmd in vim htop curl wget dig jq yq tree git; do command -v $cmd >/dev/null && echo "✅ $cmd" || echo "❌ $cmd"; done
echo "=== Histórico ===" && history 3
```

### 8.2 Teste de conectividade

```bash
ping -c 2 8.8.8.8           # internet
ping -c 2 github.com        # DNS
curl -I https://download.docker.com   # acesso ao repo Docker
```

---

## 9. Automação com Ansible (opcional)

> 💡 Todo o conteúdo desta seção pode ser automatizado. Abaixo, um **esqueleto de playbook** que reflete os passos manuais acima.

### 9.1 Estrutura sugerida

```
ansible/
├── inventory/
│   └── hosts.ini
├── group_vars/
│   └── all.yml
└── playbooks/
    └── base-ubuntu.yml
```

### 9.2 `inventory/hosts.ini`

```ini
[swarm_managers]
docker-swarm-01 ansible_host=10.0.39.31
docker-swarm-02 ansible_host=10.0.39.32
docker-swarm-03 ansible_host=10.0.39.33

[swarm_workers]
docker-swarm-04 ansible_host=10.0.39.34
docker-swarm-05 ansible_host=10.0.39.35

[swarm:children]
swarm_managers
swarm_workers

[swarm:vars]
ansible_user=joelfernandes
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
```

### 9.3 `playbooks/base-ubuntu.yml` (esqueleto)

```yaml
---
- name: Base Ubuntu para Docker Swarm
  hosts: swarm
  become: true
  tasks:
    - name: Configurar fuso horário
      community.general.timezone:
        name: America/Sao_Paulo

    - name: Atualizar cache apt
      apt:
        update_cache: yes

    - name: Atualizar sistema
      apt:
        upgrade: dist

    - name: Instalar chrony
      apt:
        name: chrony
        state: present

    - name: Configurar chrony
      copy:
        dest: /etc/chrony/chrony.conf
        content: |
          pool a.st1.ntp.br iburst
          pool b.st1.ntp.br iburst
          pool pool.ntp.org iburst
          driftfile /var/lib/chrony/chrony.drift
          rtcsync
          makestep 1 3
      notify: restart chrony

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

    - name: Parâmetros sysctl
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

    - name: Regras UFW
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop:
        - "22"
        - "2377"
        - "7946"
        - "80"
        - "443"

    - name: UFW UDP
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: udp
      loop:
        - "7946"
        - "4789"

    - name: Ativar UFW
      ufw:
        state: enabled

    - name: HISTTIMEFORMAT global
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

### 9.4 Execução

```bash
ansible-playbook -i inventory/hosts.ini playbooks/base-ubuntu.yml
```

> 💡 Ajuste o `inventory` e o `group_vars` conforme sua realidade. O playbook acima é um **ponto de partida** — teste em uma VM antes de rodar no cluster inteiro.

---

## 10. Próximos Passos

Após aplicar este documento, cada nó estará pronto para o **Doc 2 — Docker Swarm + Traefik + Portainer**:

1. ✅ Fuso horário e locale configurados
2. ✅ NTP sincronizado (chrony)
3. ✅ Ferramentas essenciais instaladas
4. ✅ Kernel preparado para Swarm
5. ✅ Firewall ativo com portas do Swarm liberadas
6. ✅ Histórico com timestamp ativo

➡️ Siga para **[02-Docker-Swarm-Traefik-Portainer.md](./02-Docker-Swarm-Traefik-Portainer.md)**

---

## 🧠 Lições Aprendidas

1. **NTP é crítico em cluster**: tokens do Swarm e certificados TLS dependem de tempo sincronizado.
2. **Swap desabilitado** é obrigatório — evita comportamento errático do scheduler.
3. **`br_netfilter` + `ip_forward`** são a base do overlay network.
4. **UFW tem limitações com Docker** — pesquise `ufw-docker` para produção.
5. **Timestamp desde o início** — sem ele, a documentação perde a ordem dos passos.
6. **Automatize com Ansible** desde o começo — mesmo que comece manual, migre para playbook.

---

*Documento gerado em 01/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
