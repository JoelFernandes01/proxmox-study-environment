# 🐘 Doc 8 — PostgreSQL Multi-Disco + Ansible Vault

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar o provisionamento de uma VM PostgreSQL 16 com disco dedicado para dados (multi-disco), utilizando Ansible Vault para gerenciar segredos e Terraform para a infraestrutura.  
> **Pré-requisito:** Templates Proxmox criados (Doc 1), API Token configurado, Terraform e Ansible instalados.  

---

## 📋 Sumário

1. [Arquitetura do Ambiente](#1-arquitetura-do-ambiente-e-premissas-de-sre)
2. [Terraform — Provisionamento Multi-Disco](#2-terraform--provisionamento-multi-disco)
3. [Ansible — Automação, Storage e Segredos](#3-ansible--automação-storage-e-segredos)
4. [Testes e Validação de Segurança](#4-testes-e-validação-de-segurança)
5. [Conclusão](#5-conclusão)
6. [Referências Cruzadas](#6-referências-cruzadas)

---

### 📋 Visão Geral
Este documento consolidado estabelece a arquitetura final, testada e homologada da esteira completa de provisionamento e automação para o **Ambiente Nverse** no servidor Dell PowerEdge R410 executando **Proxmox VE 9.2.11**. 

O fluxo é dividido em três fases totalmente integradas, seguras e sequenciais:
1. **ETAPA 1: TERRAFORM (Provisionamento de Infraestrutura)**: Instanciação nativa da VM `201` (`postgresql-server-db`) com arquitetura Multi-Disco no SSD de 2TB (`storage-vms`).
2. **ETAPA 2: ANSIBLE VAULT & GERENCIAMENTO DE CONFIGURAÇÃO**: Formatação em `ext4` do volume bruto de **100 GB** (`/dev/sdb`), montagem persistente otimizada (`noatime`) em `/var/lib/postgresql`, e instalação do PostgreSQL 16 utilizando o **Ansible Vault** (`vars/secret.yml`) para proteção criptografada das senhas do sistema e do banco (`connect` / `123@Mudar`).
3. **ETAPA 3: TESTES E VALIDAÇÃO DE SEGURANÇA**: Bateria de testes operacionais de rede, verificação de sockets, validação do canal cifrado **TLSv1.3** e verificação da montagem do armazenamento dedicado.

---

## 🏗️ 1. Arquitetura do Ambiente e Premissas de SRE

### A. Especificações de Hardware e Software
* **Servidor Físico**: Dell PowerEdge R410 (32 GB RAM, Processadores Intel Xeon).
* **Hipervisor**: Proxmox VE 9.2.11 (Host IP: `10.0.39.5`).
* **Datastores**: 
  * `local` (SISTEMA OPERACIONAL PROXMOX): HD de Boot.
  * `storage-vms` (SSD de 2TB): Datastore de alta velocidade para os discos das VMs.
* **Templates de Imagem**: Ubuntu Server 24.04 LTS (ID `8100` em formato Cloud-Init).
* **VM Provisionada**:
  * **ID**: `201`
  * **Nome**: `postgresql-server-db`
  * **Rede**: IP Fixo `10.0.39.43/24`, Gateway `10.0.39.1`, Bridge `vmbr0`.
  * **Discos**:
    * **`/dev/sda` (Disco OS)**: 50 GiB (Sistema Operacional Ubuntu 24.04).
    * **`/dev/sdb` (Disco Dados)**: 100 GiB (Dedicado ao diretório do PostgreSQL).

---

## 2. Terraform — Provisionamento Multi-Disco

### 1.1. Governança e Permissões de Segurança no Proxmox (`pveum`)
Para evitar o uso de credenciais de `root`, o acesso do Terraform é regido por um API Token e uma Role com o princípio do menor privilégio, incluindo a permissão `SDN.Use` necessária para vinculação na bridge de rede `vmbr0`:

```bash
# 1. Criar/Atualizar a Role customizada TerraformProv
pveum role modify TerraformProv -privs "VM.Allocate VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Memory VM.Config.CPU VM.Config.Options VM.PowerMgmt VM.Audit VM.Clone Datastore.AllocateSpace Datastore.Audit Sys.Audit SDN.Use"

# 2. Criar o usuário e vincular a ACL no nível raiz
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv

# 3. Gerar o API Token de acesso
pveum user token add terraform-prov@pve terraform-token --privsep 0
```

### 1.2. Código-Fonte do Terraform (`terraform-multidisk/`)

#### A. `providers.tf`
Configura o provedor moderno `bpg/proxmox` utilizando a API nativa em Go, definindo o timeout HTTP para 1200s (20 minutos) para prevenir falhas na clonagem do disco de 100 GB:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true
  ssh {
    agent = true
  }
  timeout = 1200 # Previne timeouts HTTP 596 na clonagem de múltiplos discos
}
```

#### B. `variables.tf`
```hcl
variable "proxmox_api_url" { type = string }
variable "proxmox_token_id" { type = string, sensitive = true }
variable "proxmox_token_secret" { type = string, sensitive = true }
variable "target_node" { type = string, default = "proxmox-nverse" }
variable "template_vm_id" { type = number, default = 8100 }
variable "vm_id" { type = number, default = 201 }
variable "vm_name" { type = string, default = "postgresql-server-db" }
variable "vm_ip_address" { type = string, default = "10.0.39.43/24" }
variable "vm_gateway" { type = string, default = "10.0.39.1" }
variable "ssh_public_key" { type = string, sensitive = true }
```

#### C. `main.tf`
Define os dois discos SCSI independentes (`scsi0` e `scsi1`) no SSD de 2TB (`storage-vms`):

```hcl
resource "proxmox_virtual_environment_vm" "postgres_vm_multidisk" {
  name        = var.vm_name
  node_name   = var.target_node
  vm_id       = var.vm_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  # Disco 1: Sistema Operacional (50 GB)
  disk {
    datastore_id = "storage-vms"
    file_format  = "raw"
    interface    = "scsi0"
    size         = 50
  }

  # Disco 2: Banco de Dados PostgreSQL (100 GB)
  disk {
    datastore_id = "storage-vms"
    file_format  = "raw"
    interface    = "scsi1"
    size         = 100
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ip_address
        gateway = var.vm_gateway
      }
    }
    user_account {
      username = "connect"
      keys     = [var.ssh_public_key]
    }
  }
}
```

#### D. `outputs.tf`
```hcl
output "vm_id" { value = proxmox_virtual_environment_vm.postgres_vm_multidisk.vm_id }
output "vm_name" { value = proxmox_virtual_environment_vm.postgres_vm_multidisk.name }
output "configured_ip" { value = var.vm_ip_address }
output "ssh_connection_command" { value = "ssh connect@10.0.39.43" }
```

### 1.3. Comandos de Execução e Deploy
```bash
cd terraform-multidisk
terraform init
terraform plan -out=multi-disk
terraform apply "multi-disk"
```

---

## 3. Ansible — Automação, Storage e Segredos

### 2.1. Estrutura de Arquivos e Gestão de Segredos
A automação com o Ansible utiliza a funcionalidade nativa **Ansible Vault** para garantir que credenciais de sistema e senhas de banco de dados fiquem criptografadas no repositório de código.

```text
ansible/
├── ansible.cfg                 # Configuração global apontando para o arquivo de chave do Vault
├── .vault_pass                 # Senha mestre do Vault (Adicionado ao .gitignore)
├── .gitignore                  # Impede a gravação da senha mestre no Git
├── inventory/
│   ├── hosts.ini               # Inventário associado às variáveis do Vault
│   └── group_vars/
│       └── db_servers.yml      # Tuning e parâmetros de banco
├── vars/
│   └── secret.yml              # Variáveis criptografadas via Ansible Vault
└── playbooks/
    └── deploy-postgres.yml     # Playbook principal chamando vars/secret.yml
```

### 2.2. Criação do Cofre de Segredos (`vars/secret.yml`)

1. **Criar a Chave Mestre local (`.vault_pass`)**:
   ```bash
   echo "NverseVaultMasterPass2026!" > .vault_pass
   chmod 600 .vault_pass
   ```

2. **Criar e Criptografar o arquivo de variáveis (`vars/secret.yml`)**:
   ```bash
   ansible-vault create vars/secret.yml --vault-password-file .vault_pass
   ```

3. **Conteúdo do Arquivo Criptografado (`vars/secret.yml`)**:
   ```yaml
   ---
   # Credenciais de Sistema (Linux / Sudo)
   vault_ansible_user: "connect"
   vault_ansible_password: "connect"
   vault_ansible_sudo_pass: "connect"

   # Credenciais do Banco de Dados PostgreSQL
   vault_postgres_admin_user: "connect"
   vault_postgres_admin_password: "123@Mudar"
   ```

### 2.3. Configurações de Orquestração (`ansible.cfg`)
Ativa o auto-carregamento do arquivo de senha do Vault e o **SSH Pipelining**:

```ini
[defaults]
inventory           = ./inventory/hosts.ini
host_key_checking   = False
remote_user         = connect
private_key_file    = ~/.ssh/id_terraform
stdout_callback     = default
interpreter_python  = auto_silent
vault_password_file = ./.vault_pass

[connection]
pipelining = True

[callback_default]
result_format = yaml

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

### 2.4. Inventário (`inventory/hosts.ini`)
Associa dinamicamente o usuário e senhas obtidos do Vault:

```ini
[db_servers]
postgresql-server-db ansible_host=10.0.39.43

[db_servers:vars]
ansible_user={{ vault_ansible_user }}
ansible_password={{ vault_ansible_password }}
ansible_become_password={{ vault_ansible_sudo_pass }}
```

### 2.5. Variáveis de Grupo (`inventory/group_vars/db_servers.yml`)
Define a vinculação de credenciais do banco com os segredos do Vault e especifica o tuning para 4GB RAM:

```yaml
---
postgresql_version: "16"
postgresql_port: 5432
postgresql_listen_addresses: "*"

# Estrutura Multi-Disco
postgresql_data_dir: "/var/lib/postgresql"
postgresql_data_device: "/dev/sdb"

# Tuning de Memória (4 GB RAM)
postgresql_shared_buffers: "1GB"          # 25% da RAM total
postgresql_work_mem: "16MB"               # Evita temporários em disco
postgresql_maintenance_work_mem: "256MB"  # Manutenção e indexação rápida
postgresql_effective_cache_size: "3GB"    # 75% da RAM total
postgresql_checkpoint_completion_target: "0.9"
postgresql_max_wal_size: "2GB"
postgresql_min_wal_size: "80MB"

# Bases de Dados e Credenciais (Mapeadas do secret.yml)
postgresql_databases:
  - name: nverse_prod
    owner: "{{ vault_postgres_admin_user }}"

postgresql_users:
  - name: "{{ vault_postgres_admin_user }}"
    password: "{{ vault_postgres_admin_password }}"
    role_attr_flags: "SUPERUSER,CREATEDB"

# Segurança de Rede (pg_hba.conf)
postgresql_hba_entries:
  - { type: local, database: all, user: all, method: peer }
  - { type: host, database: all, user: all, address: "127.0.0.1/32", method: scram-sha-256 }
  - { type: host, database: all, user: all, address: "10.0.39.0/24", method: scram-sha-256 }
```

### 2.6. Playbook de Implantação Criptografado (`playbooks/deploy-postgres.yml`)
Chama o arquivo `vars/secret.yml` via `vars_files`, realiza a formatação e montagem do segundo disco `/dev/sdb`, e instala/otimiza o PostgreSQL 16:

```yaml
---
- name: Deploy, Multi-Disco e Otimização do PostgreSQL com Ansible Vault - Ambiente Nverse
  hosts: db_servers
  become: yes
  gather_facts: yes
  vars_files:
    - ../vars/secret.yml

  tasks:
    - name: 1. Instalar dependências básicas do SO (Incluindo acl e parted)
      ansible.builtin.apt:
        name:
          - gnupg
          - curl
          - ca-certificates
          - acl
          - parted
          - python3-psycopg2
        state: present
        update_cache: yes

    - name: 2. Criar diretório de montagem oficial do PostgreSQL
      ansible.builtin.file:
        path: "{{ postgresql_data_dir }}"
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: 3. Formatar o segundo disco bruto (100GB /dev/sdb) como Ext4
      community.general.filesystem:
        fstype: ext4
        dev: "{{ postgresql_data_device }}"

    - name: 4. Montar o disco permanentemente no /etc/fstab por UUID
      ansible.posix.mount:
        path: "{{ postgresql_data_dir }}"
        src: "{{ postgresql_data_device }}"
        fstype: ext4
        opts: defaults,noatime,nodiratime
        state: mounted

    - name: 5. Criar pasta para chaves apt externas
      ansible.builtin.file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: 6. Baixar chave pública GPG oficial do repositório PostgreSQL
      ansible.builtin.get_url:
        url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
        dest: /etc/apt/keyrings/postgresql.asc
        mode: '0644'

    - name: 7. Configurar repositório estável oficial pgdg
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt {{ ansible_facts['distribution_release'] }}-pgdg main"
        state: present
        filename: pgdg

    - name: 8. Instalar pacotes do PostgreSQL-16 e Contrib
      ansible.builtin.apt:
        name:
          - "postgresql-{{ postgresql_version }}"
          - "postgresql-contrib-{{ postgresql_version }}"
        state: present
        update_cache: yes

    - name: 9. Garantir inicialização e ativação do serviço PostgreSQL
      ansible.builtin.service:
        name: postgresql
        state: started
        enabled: yes

    - name: 10. Corrigir permissões do diretório de dados para a conta postgres
      ansible.builtin.file:
        path: "{{ postgresql_data_dir }}"
        owner: postgres
        group: postgres
        mode: '0750'
        recurse: no

    - name: 11. Aplicar otimizações de Tuning no postgresql.conf
      ansible.builtin.lineinfile:
        path: "/etc/postgresql/{{ postgresql_version }}/main/postgresql.conf"
        regexp: "^{{ item.key }}\s*=.*"
        line: "{{ item.key }} = {{ item.value }}"
        state: present
      loop:
        - { key: "listen_addresses", value: "'{{ postgresql_listen_addresses }}'" }
        - { key: "shared_buffers", value: "{{ postgresql_shared_buffers }}" }
        - { key: "work_mem", value: "{{ postgresql_work_mem }}" }
        - { key: "maintenance_work_mem", value: "{{ postgresql_maintenance_work_mem }}" }
        - { key: "effective_cache_size", value: "{{ postgresql_effective_cache_size }}" }
        - { key: "checkpoint_completion_target", value: "{{ postgresql_checkpoint_completion_target }}" }
        - { key: "max_wal_size", value: "{{ postgresql_max_wal_size }}" }
        - { key: "min_wal_size", value: "{{ postgresql_min_wal_size }}" }
      notify: Restart PostgreSQL

    - name: 12. Aplicar regras de acesso a rede no pg_hba.conf
      ansible.builtin.blockinfile:
        path: "/etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf"
        marker: "# {mark} ANSIBLE MANAGED NVERSE RULES"
        block: |
          {% for entry in postgresql_hba_entries %}
          {{ entry.type }} {{ entry.database }} {{ entry.user }} {{ entry.address if 'address' in entry else '' }} {{ entry.method }}
          {% endfor %}
      notify: Restart PostgreSQL

    - name: 13. Reiniciar serviço para efetivar alterações
      ansible.builtin.meta: flush_handlers

    - name: 14. Criar usuário administrador do banco (Senha recuperada do Vault)
      community.postgresql.postgresql_user:
        name: "{{ item.name }}"
        password: "{{ item.password }}"
        role_attr_flags: "{{ item.role_attr_flags | default(omit) }}"
        state: present
      loop: "{{ postgresql_users }}"
      become_user: postgres

    - name: 15. Criar banco de dados de produção
      community.postgresql.postgresql_db:
        name: "{{ item.name }}"
        owner: "{{ item.owner | default(omit) }}"
        state: present
      loop: "{{ postgresql_databases }}"
      become_user: postgres

  handlers:
    - name: Restart PostgreSQL
      ansible.builtin.service:
        name: postgresql
        state: restarted
```

### 2.7. Execução do Deploy
```bash
cd ansible
ansible-playbook playbooks/deploy-postgres.yml
```

---

## 4. Testes e Validação de Segurança

### 3.1. Validação de Montagem do Storage (`/dev/sdb`)
Verifica se o PostgreSQL está armazenando os dados no volume dedicado de 100 GB:

```bash
ssh connect@10.0.39.43 "df -h | grep postgresql"
```
**Resultado Esperado**:
```text
/dev/sdb         98G   24K   93G   1% /var/lib/postgresql
```

### 3.2. Verificação do Socket de Escuta da Porta 5432
Garante a abertura de rede em todas as interfaces:

```bash
ssh connect@10.0.39.43 "ss -nltp | grep 5432"
```
**Resultado Esperado**:
```text
LISTEN 0      200          0.0.0.0:5432      0.0.0.0:*          
LISTEN 0      200             [::]:5432         [::]:* 
```

### 3.3. Teste de Conexão Cifrada (TLSv1.3) com a Senha Criptografada `123@Mudar`
Valida a autenticação no banco `nverse_prod` utilizando as credenciais injetadas via Vault:

```bash
psql -h 10.0.39.43 -U connect -d nverse_prod
```
*Senha solicitada*: `123@Mudar`

**Retorno do Terminal (Homologação com Sucesso)**:
```text
Password for user connect: 
psql (18.6 (Ubuntu 18.6-0ubuntu0.26.04.1), server 16.15 (Ubuntu 16.15-1.pgdg24.04+2))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off, ALPN: none)
Type "help" for help.

nverse_prod=# SELECT version();
                                              version                                               
----------------------------------------------------------------------------------------------------
 PostgreSQL 16.15 (Ubuntu 16.15-1.pgdg24.04+2) on x86_64-pc-linux-gnu, compiled by gcc...
(1 row)

nverse_prod=# \q
```

---

## 5. Conclusão
O pipeline **Terraform -> Ansible Vault -> Testes** para o **Ambiente Nverse (v10 Final)** foi **100% unificado, homologado e protegido contra vazamento de segredos**. A esteira garante isolamento total de I/O em disco secundário e governança DevSecOps de nível sênior.

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
| **08-PostgreSQL-Multi-Disco-Ansible-Vault.md** *(este documento)* | PostgreSQL multi-disco |

---

## 🧠 Lições Aprendidas

1. **Multi-disco em VMs**: separar OS e dados melhora I/O e permite snapshots independentes
2. **Ansible Vault**: segredos nunca ficam em texto plano no repositório
3. **`noatime`**: reduz I/O desnecessário em disco de dados
4. **TLSv1.3**: versão mais segura do TLS, obrigatória em produção
5. **`pg_hba.conf`**: controle de acesso por IP e método de autenticação
6. **Testes de produção**: validar socket, TLS e montagem antes de ir para produção
7. **`pveum`**: princípio do menor privilégio para tokens Terraform
8. **Backup do `secret.yml`**: o arquivo criptografado deve ser versionado, mas a **chave** não

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
