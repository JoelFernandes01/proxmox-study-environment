# 🏗️ Doc 2 — Provisionamento com Terraform

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar o provisionamento automatizado das VMs do cluster Docker Swarm no Proxmox via Terraform, incluindo código-fonte, execução, troubleshooting e boas práticas.  
> **Pré-requisito:** Template Proxmox criado (**[Doc 1](./01-Template-Proxmox-CloudInit.md)**), API Token configurado, Terraform instalado.

---

## 📋 Sumário

1. [Por Que Terraform?](#1-por-que-terraform)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Estrutura de Arquivos](#3-estrutura-de-arquivos)
4. [API Token no Proxmox](#4-api-token-no-proxmox)
5. [Código-Fonte](#5-código-fonte)
6. [Execução](#6-execução)
7. [Troubleshooting](#7-troubleshooting)
8. [Boas Práticas](#8-boas-práticas)
9. [Referências Cruzadas](#9-referências-cruzadas)

---

## 1. Por Que Terraform?

| Terraform | Manual (qm create) |
|-----------|---------------------|
| Declarativo | Imperativo |
| Idempotente | Frágil |
| Versionável | Difícil de rastrear |
| Reprodutível | Erro humano |
| Plan antes do apply | Sem visibilidade |

**Fluxo:**

```
terraform init     → baixa providers
terraform plan     → mostra o que será feito
terraform apply    → executa
terraform destroy  → remove tudo
```

---

## 2. Pré-requisitos

- **Proxmox 9.x** com storage `storage-vms` configurado
- **Template** `ubuntu-server-26-template` (ID `8000`) criado (**[Doc 1](./01-Template-Proxmox-CloudInit.md)**)
- **API Token** no Proxmox (ver seção 4)
- **Terraform** instalado:
  ```bash
  sudo apt update
  sudo apt install -y terraform
  terraform --version
  ```
- **Provider**: `bpg/proxmox` (baixado automaticamente pelo `terraform init`)

---

## 3. Estrutura de Arquivos

```
docker-swarm/
├── main.tf              ← recursos (VMs)
├── variables.tf         ← variáveis
├── output.tf            ← outputs (inventário Ansible)
├── providers.tf         ← provider Proxmox
├── terraform.tfvars     ← valores (⚠️ não commitar)
├── templates/
│   └── inventory.tpl    ← template do inventário Ansible
├── tfplan               ← plano salvo
└── .gitignore           ← protege .tfstate, .tfvars
```

---

## 4. API Token no Proxmox

### 4.1 Criar a Role

```bash
pveum role modify TerraformProv -privs "VM.Allocate VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Memory VM.Config.CPU VM.Config.Options VM.PowerMgmt VM.Audit VM.Clone Datastore.AllocateSpace Datastore.Audit Sys.Audit SDN.Use"
```

### 4.2 Criar o Usuário

```bash
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv
```

### 4.3 Gerar o Token

```bash
pveum user token add terraform-prov@pve terraform-token --privsep 0
```

**Saída:**

```
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ terraform-prov@pve!terraform-token   │
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
```

> ⚠️ **Guarde o `value`** — ele **não é mostrado de novo**.

---

## 5. Código-Fonte

### 5.1 `providers.tf`

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
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
  ssh {
    agent = true
  }
}
```

### 5.2 `main.tf`

```hcl
locals {
  swarm_managers = {
    for idx, name in var.swarm_managers :
    name => {
      vm_id = var.swarm_manager_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_manager_ip_start + idx)}/24"
      role  = "manager"
    }
  }

  swarm_workers = {
    for idx, name in var.swarm_workers :
    name => {
      vm_id = var.swarm_worker_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_worker_ip_start + idx)}/24"
      role  = "worker"
    }
  }

  docker_nodes = merge(local.swarm_managers, local.swarm_workers)
}

resource "proxmox_virtual_environment_vm" "docker_environment" {
  for_each = local.docker_nodes

  name        = each.key
  description = "VM ${each.value.role} do cluster Docker Swarm - provisionada via Terraform"
  tags        = ["terraform", "ubuntu-26", "docker-swarm", each.value.role, "ansible"]
  node_name   = var.target_node
  vm_id       = each.value.vm_id

  timeout_create  = 3600
  timeout_clone   = 3600
  timeout_migrate = 1800

  agent {
    enabled = true
  }

  cpu {
    cores   = tonumber(var.vm_cores)
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = tonumber(var.vm_memory)
  }

  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = tonumber(var.vm_disk_size)
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
        address = each.value.ip
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }
}
```

### 5.3 `variables.tf` (trecho principal)

```hcl
variable "proxmox_api_url" {
  type        = string
  description = "A URL de API do servidor Proxmox"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "ID do API Token gerado no Proxmox"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Secret do API Token"
  sensitive   = true
}

variable "template_vm_id" {
  type        = string
  description = "ID do template (ex: 8000)"
}

variable "swarm_managers" {
  type        = list(string)
  default     = ["docker-swarm-01", "docker-swarm-02", "docker-swarm-03"]
}

variable "swarm_workers" {
  type        = list(string)
  default     = ["docker-worker-01", "docker-worker-02", "docker-worker-03"]
}
```

### 5.4 `output.tf`

```hcl
output "docker_nodes_summary" {
  description = "Resumo das VMs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.docker_environment :
    name => {
      vm_id = vm.vm_id
      ip    = local.docker_nodes[name].ip
      role  = local.docker_nodes[name].role
    }
  }
}

output "ansible_inventory" {
  description = "Inventário Ansible"
  value = templatefile("${path.module}/templates/inventory.tpl", {
    managers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment :
      name => local.docker_nodes[name].ip
      if local.docker_nodes[name].role == "manager"
    }
    workers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment :
      name => local.docker_nodes[name].ip
      if local.docker_nodes[name].role == "worker"
    }
    vm_user = var.vm_user
  })
}
```

### 5.5 `terraform.tfvars` (⚠️ NÃO COMMITAR)

```hcl
proxmox_api_url          = "https://10.0.39.5:8006/"
proxmox_api_token_id     = "terraform-prov-des@pve!terraform-token"
proxmox_api_token_secret = "<TOKEN_SECRET>"

target_node    = "des"
template_vm_id = 8000

swarm_managers = ["docker-swarm-01", "docker-swarm-02", "docker-swarm-03"]
swarm_workers  = ["docker-worker-01", "docker-worker-02", "docker-worker-03"]

swarm_manager_ip_start    = 100
swarm_worker_ip_start     = 120
swarm_manager_vm_id_start = 9000
swarm_worker_vm_id_start  = 9010

vm_cores      = "2"
vm_memory     = "4096"
vm_storage_id = "storage-vms"
vm_disk_size  = "50"

vm_network_cidr = "10.0.39.0/24"
vm_gateway      = "10.0.39.1"
vm_bridge       = "vmbr0"

vm_user        = "connect"
ssh_public_key = "ssh-ed25519 AAAA... joel@laptop"
```

---

## 6. Execução

### 6.1 Inicializar

```bash
cd docker-swarm/
terraform init
```

### 6.2 Gerar o plano

```bash
terraform plan -out=tfplan
```

### 6.3 Revisar o plano

```bash
terraform show tfplan | grep -E "Plan:|will be created"
```

**Esperado:**

```
Plan: 6 to add, 0 to change, 0 to destroy.
```

### 6.4 Aplicar

```bash
time terraform apply -parallelism=1 tfplan
```

> ⚠️ **`-parallelism=1`** evita sobrecarregar o host (uma VM por vez).

**Tempo esperado:** ~20 minutos para 6 VMs.

### 6.5 Validar

```bash
terraform output -raw ansible_inventory > ../ansible/inventory/hosts.ini
cat ../ansible/inventory/hosts.ini
```

### 6.6 Destruir (se necessário)

```bash
terraform destroy -parallelism=1 -auto-approve
```

---

## 7. Troubleshooting

### 7.1 Timeout e Resíduos no Storage

**Sintoma:** `disk image '.../vm-XXXX-cloudinit.qcow2' already exists`.

**Causa:** timeout no `apply` deixou arquivos órfãos no storage.

**Solução:**

```bash
# No host Proxmox
qm list | grep <VM_ID>
ls /mnt/pve/storage-vms/images/<VM_ID>/

# Se NÃO houver VM ativa:
sudo rm -rf /mnt/pve/storage-vms/images/<VM_ID>/

# Recriar o plano
terraform plan -out=tfplan2
terraform apply -parallelism=1 tfplan2
```

### 7.2 State Inconsistente

**Sintoma:** `terraform state list` mostra recursos que não existem no Proxmox.

**Solução:**

```bash
terraform state rm 'proxmox_virtual_environment_vm.docker_environment["docker-swarm-01"]'
terraform plan
```

### 7.3 Token Inválido

**Sintoma:** `401 Unauthorized` ao rodar `terraform plan`.

**Causa:** token expirado ou revogado.

**Solução:** gerar novo token (seção 4.3) e atualizar `terraform.tfvars`.

---

## 8. Boas Práticas

1. **`.gitignore`**: proteger `*.tfvars`, `*.tfstate`, `.terraform/`
2. **`plan -out`**: sempre salvar o plano antes de aplicar
3. **`-parallelism=1`**: em hosts modestos
4. **`time`**: medir o tempo de cada `apply`
5. **Backup do state**: o `.tfstate.backup` é o paraquedas
6. **Nunca commitar segredos**: use `secrets.tfvars` (ignorado)
7. **`terraform fmt`**: formatação automática
8. **`terraform validate`**: validação de sintaxe

---

## 9. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Criação do template |
| **02-Provisionamento-Terraform.md** *(este documento)* | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Configuração das VMs |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação manual |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Governança |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL |
| **[09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md)** | MariaDB multi-disco |
| **[10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md)** | Servidor NFS para persistência |

---

## 🧠 Lições Aprendidas

1. **`for_each` > `count`**: recursos identificados por chave, não índice
2. **`merge()` de locals**: DRY para managers + workers
3. **`cidrhost()`**: IPs calculados, não hardcoded
4. **`-parallelism=1`**: evita sobrecarga do host
5. **`plan -out`**: aplicar exatamente o revisado
6. **Timeout ≠ falha**: verificar o estado real antes de agir
7. **Resíduos órfãos**: auditar o storage após `destroy`
8. **`.tfvars` no `.gitignore`**: nunca commitar segredos
9. **`.tfstate.backup`**: paraquedas em caso de erro
10. **`terraform fmt`**: manter formatação consistente

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
