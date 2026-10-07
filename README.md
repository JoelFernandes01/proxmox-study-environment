# 📚 Proxmox Study Environment

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentação completa do ambiente Docker Swarm + Traefik + Portainer no Proxmox VE, com provisionamento via Terraform e configuração via Ansible.

---

## 📖 Documentos

A documentação está organizada em **12 documentos** sequenciais. Recomenda-se lê-los na ordem:

| # | Documento | Assunto |
|---|-----------|---------|
| **1** | [01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md) | Criação de templates Proxmox com cloud-init |
| **2** | [02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md) | Provisionamento das VMs via Terraform |
| **3** | [03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md) | Preparação da VM (NTP, kernel, UFW, ferramentas) |
| **4** | [04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md) | Instalação manual do cluster Docker Swarm |
| **5** | [05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md) | Instalação automatizada via Ansible |
| **6** | [06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md) | Configuração detalhada do Portainer |
| **7** | [07-Governanca-Git.md](./07-Governanca-Git.md) | Governança e boas práticas de Git |
| **8** | [08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md) | PostgreSQL multi-disco com Ansible Vault |
| **9** | [09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md) | MariaDB multi-disco com Ansible Vault |
| **10** | [10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md) | Servidor NFS para persistência das stacks |
| **11** | [11-Migracao-Storage-LVM-Thin.md](./11-Migracao-Storage-LVM-Thin.md) | Migração de storage dir para LVM-Thin |
| **12** | [12-Preparando-Melhor-seu-Proxmox.md](./12-Preparando-Melhor-seu-Proxmox.md) | Boas práticas para instalação do Proxmox |

---

## 🎯 Status do Ambiente

```
┌─────────────────────────────────────────────────────┐
│  CLUSTER DOCKER SWARM — STATUS                      │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Managers (3):                                      │
│    ✅ docker-swarm-01  → 10.0.39.100 (Líder)        │
│    ✅ docker-swarm-02  → 10.0.39.101 (Reachable)    │
│    ✅ docker-swarm-03  → 10.0.39.102 (Reachable)    │
│                                                     │
│  Workers (3):                                       │
│    ✅ docker-worker-01 → 10.0.39.120 (Ready)        │
│    ✅ docker-worker-02 → 10.0.39.121 (Ready)        │
│    ✅ docker-worker-03 → 10.0.39.122 (Ready)        │
│                                                     │
│  Docker:         ✅ v29.8.2                         │
│  Swarm:          ✅ 3 managers + 3 workers          │
│  Traefik:        ✅ v2.11 (3/3 réplicas)            │
│  Portainer:      ✅ 6/6 agent + 1/1 server          │
│  DNS:            ✅ Resolvendo (.empresa.local)      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 📂 Estrutura do Repositório

```
proxmox-study-environment/
├── README.md                                       ← este arquivo
├── 01-Template-Proxmox-CloudInit.md
├── 02-Provisionamento-Terraform.md
├── 03-Base-Ubuntu-Swarm.md
├── 04-Docker-Swarm-Traefik-Portainer.md
├── 05-Ansible-Docker-Swarm.md
├── 06-Portainer-via-Ansible.md
├── 07-Governanca-Git.md
├── 08-PostgreSQL-Multi-Disco-Ansible-Vault.md
├── 09-MariaDB-Multi-Disco-Ansible-Vault.md
├── 10-NFS-Server-Ansible.md
├── 11-Migracao-Storage-LVM-Thin.md
├── 12-Preparando-Melhor-seu-Proxmox.md
└── docker-swarm/                                    ← código Terraform + Ansible
    ├── main.tf
    ├── variables.tf
    ├── output.tf
    ├── providers.tf
    ├── terraform.tfvars                            (⚠️ não commitado)
    └── ansible/
        ├── ansible.cfg
        ├── inventory/
        └── playbooks/
```

---

## 🚀 Como Usar

### 1. Clonar o repositório

```bash
git clone git@github.com:JoelFernandes01/proxmox-study-environment.git
cd proxmox-study-environment
```

### 2. Seguir a ordem dos documentos

Comece pelo **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** e siga a sequência.

### 3. Provisionar o ambiente

```bash
cd docker-swarm/
terraform init
terraform plan -out=tfplan
terraform apply -parallelism=1 tfplan
```

### 4. Configurar o cluster

```bash
cd ansible/
ansible all -m ping
ansible-playbook playbooks/01-base-ubuntu.yml
ansible-playbook playbooks/02-install-docker.yml
ansible-playbook playbooks/03-swarm.yml
ansible-playbook playbooks/05-deploy-stacks.yml
```

---

## 🔧 Tecnologias Utilizadas

| Camada | Tecnologia |
|--------|------------|
| **Hipervisor** | Proxmox VE 9.x |
| **Provisionamento** | Terraform + Provider `bpg/proxmox` |
| **Configuração** | Ansible |
| **SO** | Ubuntu 26.04 LTS |
| **Orquestração** | Docker Swarm |
| **Reverse Proxy** | Traefik v2.11 |
| **Gestão** | Portainer CE |
| **Segredos** | Ansible Vault |

---

## 📝 Convenções

### IDs de VM

| Faixa | Uso |
|-------|-----|
| `8000-8099` | Templates Ubuntu 26 |
| `8100-8199` | Templates Ubuntu 24 |
| `9000-9099` | Docker Swarm (managers) |
| `9100-9199` | Docker Swarm (workers) |

### Rede

| Recurso | Valor |
|---------|-------|
| **Rede** | `10.0.39.0/24` |
| **Gateway** | `10.0.39.1` |
| **Domínio** | `.empresa.local` |

---

## 🧠 Boas Práticas Aplicadas

- ✅ **Infraestrutura como código** (Terraform + Ansible)
- ✅ **Segredos protegidos** (Ansible Vault, `.gitignore`)
- ✅ **Templates reutilizáveis** (cloud-init)
- ✅ **Documentação sequencial** (8 docs numerados)
- ✅ **Troubleshooting documentado** (problemas reais)
- ✅ **Convenções de IDs e rede**
- ✅ **Testes de reprodutibilidade** (destroy + apply)

---

## 📄 Licença

---

*Documento gerado em 02/10/2026 como parte do roteiro oficial do ambiente de estudos.*
