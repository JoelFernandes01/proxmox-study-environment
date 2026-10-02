# 📁 Doc 10 — Servidor NFS para Persistência

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar o provisionamento de um servidor NFS para persistência de dados das stacks Docker Swarm, incluindo configuração do servidor e dos clientes.  
> **Pré-requisito:** Templates Proxmox criados (Doc 1), API Token configurado, Terraform e Ansible instalados.

---

## 📋 Sumário

1. [Arquitetura do Ambiente](#1-arquitetura-do-ambiente)
2. [Terraform — Provisionamento](#2-terraform--provisionamento)
3. [Ansible — Servidor NFS](#3-ansible--servidor-nfs)
4. [Ansible — Clientes NFS](#4-ansible--clientes-nfs)
5. [Testes e Validação](#5-testes-e-validação)
6. [Comparativo com Produção](#6-comparativo-com-produção)
7. [Referências Cruzadas](#7-referências-cruzadas)

---

## 1. Arquitetura do Ambiente

### A. Especificações

| Item | Valor |
|------|-------|
| **Hipervisor** | Proxmox VE 9.x |
| **VM ID** | `203` |
| **Nome** | `nfs-server` |
| **IP** | `10.0.39.45/24` |
| **Gateway** | `10.0.39.1` |
| **Bridge** | `vmbr0` |
| **Template** | Ubuntu 26.04 LTS (ID `8000`) |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disco OS** (`/dev/sda`) | 50 GB |
| **Disco Dados** (`/dev/sdb`) | 500 GB |
| **Storage** | `storage-vms` |

### B. Arquitetura

```
┌─────────────────────────────────────────────────┐
│  VM nfs-server (10.0.39.45)                     │
├─────────────────────────────────────────────────┤
│                                                  │
│  /dev/sda (50 GB) — OS Ubuntu 26.04             │
│    └── / (raiz)                                 │
│                                                  │
│  /dev/sdb (500 GB) — Dados NFS                  │
│    └── /srv/nfs/swarm (ext4, noatime)           │
│                                                  │
│  Serviço: nfs-kernel-server (porta 2049)        │
│  Export: /srv/nfs/swarm → 10.0.39.0/24          │
│                                                  │
└─────────────────────────────────────────────────┘
```

### C. Estrutura de Diretórios

```
/srv/nfs/swarm/
├── glpi_data/          → GLPI (dados)
├── nginx_html/         → Nginx (html estático)
├── portainer_data/     → Portainer (config)
├── semaphore_data/     → Semaphore (dados)
├── stacks/             → Arquivos YAML das stacks
├── traefik_data/       → Traefik (certificados, config)
└── zabbix_data/        → Zabbix (dados)
```

### D. Clientes NFS

| Cliente | IP | Vai montar NFS? |
|---------|-----|-----------------|
| `docker-swarm-01` | `10.0.39.100` | ✅ |
| `docker-swarm-02` | `10.0.39.101` | ✅ |
| `docker-swarm-03` | `10.0.39.102` | ✅ |
| `docker-worker-01` | `10.0.39.120` | ✅ |
| `docker-worker-02` | `10.0.39.121` | ✅ |
| `docker-worker-03` | `10.0.39.122` | ✅ |

**Total**: 6 clientes NFS.

### E. Fluxo de Dados

```
┌─────────────────────────────────────────────────┐
│  Cliente NFS (manager ou worker)                │
│         ↓ /srv/nfs/swarm (mount NFSv4)          │
├─────────────────────────────────────────────────┤
│  Servidor NFS (10.0.39.45)                      │
│         ↓ /srv/nfs/swarm (diretório local)      │
├─────────────────────────────────────────────────┤
│  Disco dedicado (/dev/sdb, 500 GB)              │
└─────────────────────────────────────────────────┘
```

---

## 2. Terraform — Provisionamento

### 2.1. Código-Fonte

**Arquivo:** `terraform-nfs/main.tf`

```hcl
resource "proxmox_virtual_environment_vm" "nfs_server" {
  name        = "nfs-server"
  description = "Servidor NFS para persistência das stacks Swarm"
  tags        = ["terraform", "ubuntu-26", "nfs", "ansible"]
  node_name   = var.target_node
  vm_id       = 203

  timeout_create  = 3600
  timeout_clone   = 3600
  timeout_migrate = 1800

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = 50
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi1"
    size         = 500
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"

  clone {
    vm_id        = tonumber(var.template_vm_id)
    datastore_id = var.vm_storage_id
  }

  network_device {
    bridge = var.vm_bridge
  }

  initialization {
    datastore_id = var.vm_storage_id

    ip_config {
      ipv4 {
        address = "10.0.39.45/24"
        gateway = "10.0.39.1"
      }
    }

    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }
}
```

### 2.2. Comandos

```bash
cd terraform-nfs/
terraform init
terraform plan -out=tfplan
terraform apply -parallelism=1 tfplan
```

### 2.3. Validar

```bash
ssh connect@10.0.39.45 "hostname -f && ip -4 addr show | grep inet"
ssh connect@10.0.39.45 "lsblk"
```

---

## 3. Ansible — Servidor NFS

### 3.1. Estrutura

```
ansible-nfs/
├── ansible.cfg
├── inventory/
│   └── hosts.ini
└── playbooks/
    ├── deploy-nfs-server.yml
    └── deploy-nfs-clients.yml
```

### 3.2. Inventário

**Arquivo:** `ansible-nfs/inventory/hosts.ini`

```ini
[nfs_server]
nfs-server ansible_host=10.0.39.45 ansible_user=connect

[swarm]
docker-swarm-01 ansible_host=10.0.39.100
docker-swarm-02 ansible_host=10.0.39.101
docker-swarm-03 ansible_host=10.0.39.102
docker-worker-01 ansible_host=10.0.39.120
docker-worker-02 ansible_host=10.0.39.121
docker-worker-03 ansible_host=10.0.39.122

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### 3.3. Configuração do Ansible

**Arquivo:** `ansible-nfs/ansible.cfg`

```ini
[defaults]
inventory = ./inventory/hosts.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = default
result_format = yaml

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
```

### 3.4. Playbook do Servidor

**Arquivo:** `ansible-nfs/playbooks/deploy-nfs-server.yml`

```yaml
---
- name: Configurar servidor NFS
  hosts: nfs_server
  become: true
  gather_facts: true

  tasks:
    - name: Verificar se /dev/sdb já está formatado
      command: blkid /dev/sdb
      register: sdb_check
      changed_when: false
      failed_when: false

    - name: Formatar /dev/sdb como ext4
      filesystem:
        fstype: ext4
        dev: /dev/sdb
      when: sdb_check.rc != 0

    - name: Criar ponto de montagem
      file:
        path: /srv/nfs/swarm
        state: directory
        mode: '0755'

    - name: Montar /dev/sdb em /srv/nfs/swarm
      mount:
        path: /srv/nfs/swarm
        src: /dev/sdb
        fstype: ext4
        opts: "noatime,nodiratime"
        state: mounted

    - name: Instalar nfs-kernel-server
      apt:
        name:
          - nfs-kernel-server
          - nfs-common
        state: present
        update_cache: yes

    - name: Criar diretórios das stacks
      file:
        path: "/srv/nfs/swarm/{{ item }}"
        state: directory
        owner: nobody
        group: nogroup
        mode: '0777'
      loop:
        - glpi_data
        - nginx_html
        - portainer_data
        - semaphore_data
        - stacks
        - traefik_data
        - zabbix_data

    - name: Configurar /etc/exports
      copy:
        dest: /etc/exports
        content: |
          # Export NFS para o cluster Docker Swarm
          /srv/nfs/swarm 10.0.39.0/24(rw,sync,no_subtree_check,no_root_squash)
      notify: reload exports

    - name: Permitir NFS no UFW (TCP)
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop:
        - "2049"
        - "111"

    - name: Permitir NFS no UFW (UDP)
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: udp
      loop:
        - "2049"
        - "111"

    - name: Habilitar e iniciar NFS
      systemd:
        name: nfs-kernel-server
        enabled: yes
        state: started

  handlers:
    - name: reload exports
      command: exportfs -ra
```

### 3.5. Execução

```bash
cd ansible-nfs/
ansible all -m ping
ansible-playbook playbooks/deploy-nfs-server.yml
```

---

## 4. Ansible — Clientes NFS

### 4.1. Playbook dos Clientes

**Arquivo:** `ansible-nfs/playbooks/deploy-nfs-clients.yml`

```yaml
---
- name: Configurar clientes NFS
  hosts: swarm
  become: true
  gather_facts: true

  tasks:
    - name: Instalar nfs-common
      apt:
        name: nfs-common
        state: present
        update_cache: yes

    - name: Criar ponto de montagem
      file:
        path: /srv/nfs/swarm
        state: directory
        mode: '0755'

    - name: Adicionar NFS ao /etc/fstab
      lineinfile:
        path: /etc/fstab
        line: "10.0.39.45:/srv/nfs/swarm /srv/nfs/swarm nfs rw,nolock,hard,intr,noatime,_netdev,bg,nfsvers=4 0 0"
        state: present

    - name: Montar NFS
      mount:
        path: /srv/nfs/swarm
        src: "10.0.39.45:/srv/nfs/swarm"
        fstype: nfs
        opts: "rw,nolock,hard,intr,noatime,_netdev,bg,nfsvers=4"
        state: mounted
```

### 4.2. Execução

```bash
ansible-playbook playbooks/deploy-nfs-clients.yml
```

---

## 5. Testes e Validação

### 5.1. Servidor — showmount

```bash
ssh connect@10.0.39.45 "sudo showmount -e localhost"
```

**Esperado:**

```
Export list for localhost:
/srv/nfs/swarm 10.0.39.0/24
```

### 5.2. Clientes — mount

```bash
for ip in 10.0.39.100 10.0.39.101 10.0.39.102 10.0.39.120 10.0.39.121 10.0.39.122; do
  echo "=== $ip ==="
  ssh connect@$ip "mount | grep nfs"
done
```

**Esperado:**

```
10.0.39.45:/srv/nfs/swarm on /srv/nfs/swarm type nfs4 (rw,relatime,...)
```

### 5.3. Teste de escrita/leitura

```bash
ssh connect@10.0.39.100 "echo 'teste' | sudo tee /srv/nfs/swarm/stacks/teste.txt"
ssh connect@10.0.39.101 "cat /srv/nfs/swarm/stacks/teste.txt"
```

**Esperado:** `teste` (lido de outro cliente).

### 5.4. nfsstat -m

```bash
ssh connect@10.0.39.100 "nfsstat -m"
```

**Esperado:**

```
/srv/nfs/swarm from 10.0.39.45:/srv/nfs/swarm
 Flags: rw,relatime,vers=4.2,rsize=524288,wsize=524288,hard,intr,...
```

### 5.5. Persistência (reboot)

```bash
ssh connect@10.0.39.100 "sudo reboot"
sleep 60
ssh connect@10.0.39.100 "mount | grep nfs"
```

**Esperado:** NFS montado automaticamente após reboot.

---

## 6. Comparativo com Produção

| Item | Produção | Lab (Doc 10) |
|------|----------|--------------|
| **IP do NFS** | `10.0.39.40` | `10.0.39.45` |
| **Versão do NFS** | NFSv4.2 | NFSv4.2 |
| **rsize/wsize** | 524288 (512 KB) | 524288 (512 KB) |
| **fstab — opções** | `rw,nolock,hard,nfsvers=4` | `rw,nolock,hard,intr,noatime,_netdev,bg,nfsvers=4` |
| **Estrutura** | 7 diretórios | 7 diretórios (mesma) |
| **Clientes** | Managers | Managers + Workers |

### Melhorias Aplicadas no Lab

| # | Melhoria | Motivo |
|---|----------|--------|
| 1 | **`intr`** no `fstab` | Permite interromper operações travadas |
| 2 | **`noatime`** no `fstab` | Reduz I/O desnecessário |
| 3 | **`_netdev`** no `fstab` | Monta só quando a rede está pronta |
| 4 | **`bg`** no `fstab` | Tenta montar em background se falhar |

---

## 7. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL multi-disco |
| **[09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md)** | MariaDB multi-disco |
| **10-NFS-Server-Ansible.md** *(este documento)* | Servidor NFS para persistência |

---

## 🧠 Lições Aprendidas

1. **NFSv4.2** é a versão mais moderna e segura (usar sempre)
2. **Multi-disco** separa OS e dados (melhor I/O e snapshots)
3. **`hard,intr`** evita travar sem poder interromper
4. **`_netdev`** garante montagem só após a rede
5. **`bg`** tenta montar em background (não bloqueia o boot)
6. **`no_root_squash`** no `/etc/exports` mantém permissões do root (necessário para Docker)
7. **Estrutura de diretórios** por serviço facilita organização
8. **Validar com reboot** é essencial (fstab pode falhar)
9. **NFS não é backup** — é armazenamento compartilhado

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial de reprodução do ambiente de estudos.*
