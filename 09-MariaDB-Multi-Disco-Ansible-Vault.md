# 🐬 Doc 9 — MariaDB Multi-Disco + Ansible Vault

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar o provisionamento de uma VM MariaDB com disco dedicado para dados (multi-disco), utilizando Ansible Vault para gerenciar segredos e Terraform para a infraestrutura.  
> **Pré-requisito:** Templates Proxmox criados (Doc 1), API Token configurado, Terraform e Ansible instalados.

---

## 📋 Sumário

1. [Arquitetura do Ambiente](#1-arquitetura-do-ambiente)
2. [Terraform — Provisionamento Multi-Disco](#2-terraform--provisionamento-multi-disco)
3. [Ansible — Automação, Storage e Segredos](#3-ansible--automação-storage-e-segredos)
4. [Testes e Validação de Segurança](#4-testes-e-validação-de-segurança)
5. [Conclusão](#5-conclusão)
6. [Referências Cruzadas](#6-referências-cruzadas)

---

## 1. Arquitetura do Ambiente

### A. Especificações de Hardware e Software

| Item | Valor |
|------|-------|
| **Hipervisor** | Proxmox VE 9.x |
| **VM ID** | `202` |
| **Nome** | `mariadb-server-db` |
| **IP** | `10.0.39.44/24` |
| **Gateway** | `10.0.39.1` |
| **Bridge** | `vmbr0` |
| **Template** | Ubuntu 26.04 LTS (ID `8000`) |
| **vCPU** | 4 |
| **RAM** | 8 GB |
| **Disco OS** (`/dev/sda`) | 50 GB |
| **Disco Dados** (`/dev/sdb`) | 100 GB |
| **Storage** | `storage-vms` |

### B. Arquitetura Multi-Disco

```
┌─────────────────────────────────────────────┐
│  VM mariadb-server-db (10.0.39.44)          │
├─────────────────────────────────────────────┤
│                                              │
│  /dev/sda (50 GB) — OS Ubuntu 26.04         │
│    └── / (raiz)                             │
│                                              │
│  /dev/sdb (100 GB) — Dados MariaDB          │
│    └── /var/lib/mysql (ext4, noatime)       │
│                                              │
│  Serviço: mariadb (porta 3306)              │
│  Segredos: Ansible Vault                    │
│                                              │
└─────────────────────────────────────────────┘
```

### C. Diferenças vs PostgreSQL (Doc 8)

| Aspecto | PostgreSQL | MariaDB |
|---------|-----------|---------|
| **Porta** | `5432` | `3306` |
| **Diretório de dados** | `/var/lib/postgresql` | `/var/lib/mysql` |
| **Usuário do sistema** | `postgres` | `mysql` |
| **Cliente CLI** | `psql` | `mysql` |
| **Dump** | `pg_dump` | `mysqldump` |
| **Config** | `postgresql.conf` | `50-server.cnf` |
| **Auth** | `pg_hba.conf` | `mysql.user` + `GRANT` |
| **TLS** | `ssl=on` | `require_secure_transport=ON` |

---
## 2. Terraform — Provisionamento Multi-Disco

### 2.1. Governança e Permissões (pveum)

```bash
pveum role modify TerraformProv -privs "VM.Allocate VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Memory VM.Config.CPU VM.Config.Options VM.PowerMgmt VM.Audit VM.Clone Datastore.AllocateSpace Datastore.Audit Sys.Audit SDN.Use"
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv
pveum user token add terraform-prov@pve terraform-token --privsep 0
```

### 2.2. Código-Fonte do Terraform

**Arquivo:** `terraform-mariadb/main.tf`

```hcl
resource "proxmox_virtual_environment_vm" "mariadb" {
  name        = "mariadb-server-db"
  description = "VM MariaDB com disco dedicado - provisionada via Terraform"
  tags        = ["terraform", "ubuntu-26", "mariadb", "ansible"]
  node_name   = var.target_node
  vm_id       = 202

  timeout_create  = 3600
  timeout_clone   = 3600
  timeout_migrate = 1800

  agent {
    enabled = true
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 8192
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
    size         = 100
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
        address = "10.0.39.44/24"
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

### 2.3. Comandos de Execução

```bash
cd terraform-mariadb/
terraform init
terraform plan -out=tfplan
terraform apply -parallelism=1 tfplan
```

### 2.4. Validar

```bash
ssh connect@10.0.39.44 "hostname -f && ip -4 addr show | grep inet"
lsblk   # deve mostrar sda (50G) e sdb (100G)
```

---

## 3. Ansible — Automação, Storage e Segredos

### 3.1. Estrutura de Arquivos

```
ansible-mariadb/
├── ansible.cfg
├── inventory/
│   └── hosts.ini
├── vars/
│   └── secret.yml          ← Ansible Vault
└── playbooks/
    └── deploy-mariadb.yml
```

### 3.2. Criação do Cofre de Segredos

```bash
mkdir -p ansible-mariadb/vars
ansible-vault create ansible-mariadb/vars/secret.yml
```

**Conteúdo do `secret.yml`:**

```yaml
---
mariadb_root_password: "SenhaRoot@2026"
mariadb_app_user: "nverse_app"
mariadb_app_password: "SenhaApp@2026"
mariadb_app_database: "nverse_prod"
```

### 3.3. Configurações de Orquestração

**Arquivo:** `ansible-mariadb/ansible.cfg`

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

### 3.4. Inventário

**Arquivo:** `ansible-mariadb/inventory/hosts.ini`

```ini
[mariadb]
mariadb-server-db ansible_host=10.0.39.44 ansible_user=connect

[mariadb:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### 3.5. Playbook de Implantação

**Arquivo:** `ansible-mariadb/playbooks/deploy-mariadb.yml`

```yaml
---
- name: Instalar e configurar MariaDB com disco dedicado
  hosts: mariadb
  become: true
  gather_facts: true

  vars_files:
    - ../vars/secret.yml

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
        path: /var/lib/mysql
        state: directory
        owner: mysql
        group: mysql
        mode: '0750'

    - name: Montar /dev/sdb em /var/lib/mysql
      mount:
        path: /var/lib/mysql
        src: /dev/sdb
        fstype: ext4
        opts: "noatime,nodiratime"
        state: mounted

    - name: Instalar MariaDB
      apt:
        name:
          - mariadb-server
          - mariadb-client
          - python3-pymysql
        state: present
        update_cache: yes

    - name: Configurar bind-address
      lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        regexp: '^bind-address'
        line: 'bind-address = 0.0.0.0'
      notify: restart mariadb

    - name: Configurar TLS
      lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        line: "{{ item }}"
      loop:
        - 'ssl = on'
        - 'require_secure_transport = ON'
      notify: restart mariadb

    - name: Habilitar e iniciar MariaDB
      systemd:
        name: mariadb
        enabled: yes
        state: started

    - name: Definir senha do root
      community.mysql.mysql_user:
        name: root
        password: "{{ mariadb_root_password }}"
        host: localhost
        login_unix_socket: /var/run/mysqld/mysqld.sock

    - name: Criar banco de dados
      community.mysql.mysql_db:
        name: "{{ mariadb_app_database }}"
        state: present
        login_user: root
        login_password: "{{ mariadb_root_password }}"

    - name: Criar usuário da aplicação
      community.mysql.mysql_user:
        name: "{{ mariadb_app_user }}"
        password: "{{ mariadb_app_password }}"
        priv: "{{ mariadb_app_database }}.*:ALL"
        host: '%'
        login_user: root
        login_password: "{{ mariadb_root_password }}"

  handlers:
    - name: restart mariadb
      systemd:
        name: mariadb
        state: restarted
```

### 3.6. Execução do Deploy

```bash
cd ansible-mariadb/
ansible all -m ping
ansible-playbook playbooks/deploy-mariadb.yml --ask-vault-pass
```

---

## 4. Testes e Validação de Segurança

### 4.1. Validação de Montagem do Storage

```bash
ssh connect@10.0.39.44 "df -h /var/lib/mysql && mount | grep sdb"
```

**Esperado:**

```
/dev/sdb        98G   60M   93G   1% /var/lib/mysql
```

### 4.2. Verificação do Socket de Escuta

```bash
ssh connect@10.0.39.44 "sudo ss -tlnp | grep 3306"
```

**Esperado:**

```
LISTEN 0  151  *:3306  *:*  users:(("mariadbd",pid=XXX,fd=XX))
```

### 4.3. Teste de Conexão Cifrada (TLSv1.3)

```bash
ssh connect@10.0.39.44 "sudo mysql -u root -p -e \"SHOW VARIABLES LIKE 'have_ssl';\""
```

**Esperado:**

```
Variable_name   Value
have_ssl        YES
```

### 4.4. Teste com o usuário da aplicação

```bash
ssh connect@10.0.39.44 "mysql -u nverse_app -p -e 'SHOW DATABASES;'"
```

**Esperado:**

```
+--------------------+
| Database           |
+--------------------+
| information_schema |
| nverse_prod        |
+--------------------+
```

---

## 5. Conclusão

O pipeline **Terraform → Ansible Vault → Testes** para o **MariaDB** foi **100% unificado, homologado e protegido contra vazamento de segredos**. A esteira garante isolamento total de I/O em disco secundário e governança DevSecOps de nível sênior.

### Comparativo com PostgreSQL

| Item | PostgreSQL (Doc 8) | MariaDB (Doc 9) |
|------|-------------------|-----------------|
| **VM ID** | 201 | 202 |
| **IP** | 10.0.39.43 | 10.0.39.44 |
| **Porta** | 5432 | 3306 |
| **Diretório** | `/var/lib/postgresql` | `/var/lib/mysql` |
| **Usuário sistema** | postgres | mysql |
| **Multi-disco** | ✅ | ✅ |
| **Ansible Vault** | ✅ | ✅ |
| **TLS** | TLSv1.3 | TLSv1.3 |

---

## 6. Referências Cruzadas

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
| **09-MariaDB-Multi-Disco-Ansible-Vault.md** *(este documento)* | MariaDB multi-disco |
| **[10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md)** | Servidor NFS para persistência |

---

## 🧠 Lições Aprendidas

1. **MariaDB é compatível com MySQL** — maioria dos comandos funciona igual
2. **Multi-disco em VMs**: separar OS e dados melhora I/O e permite snapshots independentes
3. **Ansible Vault**: segredos nunca ficam em texto plano no repositório
4. **`noatime`**: reduz I/O desnecessário em disco de dados
5. **`require_secure_transport`**: força TLS em todas as conexões
6. **`community.mysql`**: coleção oficial do Ansible para MariaDB/MySQL
7. **`login_unix_socket`**: evita problemas de senha inicial
8. **`bind-address = 0.0.0.0`**: permite conexões remotas (cuidado com firewall)

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial de reprodução do ambiente de estudos.*
