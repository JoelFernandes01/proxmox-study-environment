### 🐧 Doc 3 — Preparação da Base Ubuntu para Kubernetes
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a preparação do sistema operacional Ubuntu em cada nó do cluster Kubernetes (desativação permanente de swap, módulos de kernel `overlay`/`br_netfilter`, parâmetros `sysctl`, sincronização `chrony` e regras de firewall UFW).  
**Pré-requisito:** VMs provisionadas pelo Terraform (**Doc 2**), acesso SSH configurado.

---

#### 📋 Sumário
1. [Desativação Permanente de Swap](#1-desativação-permanente-de-swap)
2. [Carga de Módulos de Kernel](#2-carga-de-módulos-de-kernel)
3. [Ajuste de Parâmetros de Rede Sysctl](#3-ajuste-de-parâmetros-de-rede-sysctl)
4. [Sincronização de Tempo com Chrony](#4-sincronização-de-tempo-com-chrony)
5. [Configuração de Firewall (UFW) por Papel](#5-configuração-de-firewall-ufw-por-papel)
6. [Timestamp e Histórico do Bash](#6-timestamp-e-histórico-do-bash)
7. [Playbook Ansible de Automação (00-prepara-so.yml)](#7-playbook-ansible-de-automação)

---

#### 1. Desativação Permanente de Swap
O Kubelet exige que a memória swap esteja totalmente desabilitada para garantir previsibilidade de recursos.

```bash
# Desativar em tempo de execução
sudo swapoff -a

# Comentar a linha de swap no /etc/fstab para ser permanente
sudo sed -i '/ swap / s/^\(.*\)$/# \1/g' /etc/fstab

# Validar
free -h | grep -i swap
# Esperado: Swap: 0B 0B 0B
```

---

#### 2. Carga de Módulos de Kernel
Módulos exigidos pelo container runtime (containerd) e pelo plugin CNI:

```bash
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Validação
lsmod | grep -E "overlay|br_netfilter"
```

---

#### 3. Ajuste de Parâmetros de Rede Sysctl

```bash
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Validação
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
# Esperado: ambos = 1
```

---

#### 4. Sincronização de Tempo com Chrony

```bash
sudo apt update && sudo apt install -y chrony

sudo tee /etc/chrony/chrony.conf <<EOF
pool a.st1.ntp.br iburst
pool b.st1.ntp.br iburst
pool pool.ntp.org iburst
driftfile /var/lib/chrony/chrony.drift
rtcsync
makestep 1 3
EOF

sudo systemctl restart chrony && sudo systemctl enable chrony
chronyc tracking
```

---

#### 5. Configuração de Firewall (UFW) por Papel

##### Control Planes
```bash
sudo ufw allow 6443/tcp   # Kubernetes API Server
sudo ufw allow 2379:2380/tcp # etcd server client API
sudo ufw allow 10250/tcp  # Kubelet API
sudo ufw allow 10259/tcp  # kube-scheduler
sudo ufw allow 10257/tcp  # kube-controller-manager
```

##### Worker Nodes
```bash
sudo ufw allow 10250/tcp  # Kubelet API
sudo ufw allow 30000:32767/tcp # NodePort Services
```

##### Comum a Todos os Nós (CNI Calico e SSH)
```bash
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 179/tcp    # Calico BGP
sudo ufw allow 4789/udp   # Calico VXLAN
sudo ufw allow 5473/tcp   # Calico Typha
sudo ufw enable
```

---

#### 6. Timestamp e Histórico do Bash

```bash
echo 'export HISTTIMEFORMAT="%F %T "' | sudo tee -a /etc/bash.bashrc
source /etc/bash.bashrc
```

---

#### 7. Playbook Ansible de Automação (`playbooks/base/00-prepara-so.yml`)

Este playbook executa os passos acima automaticamente em todos os 9 nós do inventário:

```yaml
---
- name: 00 - Prepara SO Base para Kubernetes
  hosts: all
  become: yes
  tasks:
    - name: Desativa Swap (runtime)
      command: swapoff -a
      changed_when: false

    - name: Desativa Swap (/etc/fstab)
      replace:
        path: /etc/fstab
        regexp: '^([^#].*\sswap\s.*)$'
        replace: '# \1'

    - name: Carrega Módulos do Kernel
      copy:
        dest: /etc/modules-load.d/k8s.conf
        content: |
          overlay
          br_netfilter

    - name: Executa modprobe
      modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - overlay
        - br_netfilter

    - name: Configura Sysctl para K8s
      copy:
        dest: /etc/sysctl.d/k8s.conf
        content: |
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1

    - name: Aplica Sysctl
      command: sysctl --system
```

---

- **Próximo Passo**: **[04-Keepalived-HAProxy-LB.md](./04-Keepalived-HAProxy-LB.md)**.
