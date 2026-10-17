### 🏗 Doc 2 — Provisionamento do Cluster Kubernetes com Terraform
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a automação da infraestrutura (IaC) para o cluster Kubernetes HA de 9 VMs no Proxmox VE utilizando o provider `bpg/proxmox`, incluindo estratégias de execução por etapas para prevenir gargalos de I/O de disco.  
**Pré-requisito:** Template Proxmox criado (**Doc 1**), API Token gerado no Proxmox VE e Terraform instalado.

---

#### 📋 Sumário
1. [Visão Geral e Arquitetura](#1-visão-geral-e-arquitetura)
2. [Configuração de Permissões e API Token no Proxmox](#2-configuração-de-permissões-e-api-token-no-proxmox)
3. [Estrutura do Código Terraform](#3-estrutura-do-código-terraform)
4. [Código-Fonte Completo](#4-código-fonte-completo)
5. [Estratégia de Provisionamento por Etapas (Evitando Gargalos de I/O)](#5-estratégia-de-provisionamento-por-etapas)
6. [Execução e Validação dos Outputs](#6-execução-e-validação-dos-outputs)
7. [Troubleshooting & Referências Cruzadas](#7-troubleshooting--referências-cruzadas)

---

#### 1. Visão Geral e Arquitetura
O Terraform gerencia a criação declarativa de 9 VMs distribuídas em 4 papéis:
- **HAProxy / Keepalived (2 VMs)**: `k8s-haproxy-01` e `02` (IDs 9400, 9401)
- **Control Planes (3 VMs)**: `k8s-control-plane-01` a `03` (IDs 9402 a 9404)
- **Worker Nodes (3 VMs)**: `k8s-worker-01` a `03` (IDs 9405 a 9407)
- **NFS Server (1 VM)**: `k8s-nfs-01` (ID 9408)

---

#### 2. Configuração de Permissões e API Token no Proxmox
No terminal do host Proxmox VE, execute os comandos de pveum:

```bash
# 1. Criar Role com permissões necessárias (incluindo SDN.Use)
pveum role modify TerraformProv -privs "VM.Allocate VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Memory VM.Config.CPU VM.Config.Options VM.PowerMgmt VM.Audit VM.Clone Datastore.AllocateSpace Datastore.Audit Sys.Audit SDN.Use"

# 2. Criar Usuário e Associar ACL
pveum user add terraform-prov@pve
pveum aclmod / -user terraform-prov@pve -role TerraformProv

# 3. Gerar API Token sem separação de privilégios
pveum user token add terraform-prov@pve terraform-token --privsep 0
```

---

#### 3. Estrutura do Código Terraform
```
kubernetes-environment/
├── providers.tf         ← Versão do provider bpg/proxmox e endpoint
├── variables.tf         ← Variáveis de configuração e IPs
├── main.tf              ← Definição das VMs via for_each
├── output.tf            ← Sumário do cluster e IPs para inventário
├── terraform.tfvars     ← Credenciais
└── .gitignore           ← Bloqueio de arquivos de estado (.tfstate)
```

---

#### 4. Código-Fonte Completo

##### `providers.tf`
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
  timeout = 1200
}
```

##### `main.tf`
```hcl
locals {
  k8s_nodes = {
    "k8s-haproxy-01"      = { vm_id = 9400, ip = "10.0.39.41/24", role = "haproxy",       cores = 2, memory = 4096, disk = 50 }
    "k8s-haproxy-02"      = { vm_id = 9401, ip = "10.0.39.42/24", role = "haproxy",       cores = 2, memory = 4096, disk = 50 }
    "k8s-control-plane-01"= { vm_id = 9402, ip = "10.0.39.43/24", role = "control-plane", cores = 2, memory = 4096, disk = 50 }
    "k8s-control-plane-02"= { vm_id = 9403, ip = "10.0.39.44/24", role = "control-plane", cores = 2, memory = 4096, disk = 50 }
    "k8s-control-plane-03"= { vm_id = 9404, ip = "10.0.39.45/24", role = "control-plane", cores = 2, memory = 4096, disk = 50 }
    "k8s-worker-01"       = { vm_id = 9405, ip = "10.0.39.61/24", role = "worker",        cores = 2, memory = 4096, disk = 50 }
    "k8s-worker-02"       = { vm_id = 9406, ip = "10.0.39.62/24", role = "worker",        cores = 2, memory = 4096, disk = 50 }
    "k8s-worker-03"       = { vm_id = 9407, ip = "10.0.39.63/24", role = "worker",        cores = 2, memory = 4096, disk = 50 }
    "k8s-nfs-01"          = { vm_id = 9408, ip = "10.0.39.70/24", role = "nfs",           cores = 2, memory = 2048, disk = 100 }
  }
}

resource "proxmox_virtual_environment_vm" "k8s" {
  for_each  = local.k8s_nodes

  name        = each.key
  description = "VM ${each.value.role} do cluster Kubernetes HA"
  tags        = ["terraform", "ubuntu-24", "kubernetes", each.value.role]
  node_name   = var.target_node
  vm_id       = each.value.vm_id

  agent {
    enabled = true
  }

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = each.value.disk
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"

  clone {
    vm_id        = tonumber(var.template_vm_id)
    datastore_id = var.vm_storage_id
    full         = true
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

---

#### 5. Estratégia de Provisionamento por Etapas

Para evitar sobrecarga de I/O no Proxmox durante o clone simultâneo de 9 VMs:

```bash
# 1. Provisionar Servidor NFS
terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-nfs-01"]' -parallelism=1 -auto-approve

# 2. Provisionar Control Planes (01 a 03)
terraform apply \
  -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-01"]' \
  -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-02"]' \
  -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-03"]' \
  -parallelism=1 -auto-approve

# 3. Provisionar Workers (01 a 03)
terraform apply \
  -target='proxmox_virtual_environment_vm.k8s["k8s-worker-01"]' \
  -target='proxmox_virtual_environment_vm.k8s["k8s-worker-02"]' \
  -target='proxmox_virtual_environment_vm.k8s["k8s-worker-03"]' \
  -parallelism=1 -auto-approve

# 4. Provisionar Load Balancers (HAProxy 01 e 02)
terraform apply \
  -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-01"]' \
  -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-02"]' \
  -parallelism=1 -auto-approve

# 5. Consolidação Geral
terraform apply -parallelism=1 -auto-approve
```

---

#### 6. Execução e Validação dos Outputs

```bash
terraform output -json k8s_nodes_summary
```

---

#### 7. Troubleshooting & Referências Cruzadas
- **Imagem residual no Proxmox**: Se um `apply` for interrompido, remova manualmente a pasta do ID em `/mnt/pve/<storage>/images/<VM_ID>` antes de rodar novamente.
- **Próximo Passo**: **[03-Base-Ubuntu-Kubernetes.md](./03-Base-Ubuntu-Kubernetes.md)**.
