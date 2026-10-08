# 🐳 Docker Swarm Environment

> **Documentação do ambiente Docker Swarm** com Traefik + Portainer.

---

## 📖 Documentos

| # | Documento | Assunto |
|---|-----------|---------|
| **1** | [01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md) | Templates Proxmox com cloud-init |
| **2** | [02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md) | Provisionamento das VMs via Terraform |
| **3** | [03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md) | Preparação da VM (NTP, kernel, UFW) |
| **4** | [04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md) | Instalação manual do cluster |
| **5** | [05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md) | Instalação automatizada via Ansible |
| **6** | [06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md) | Configuração detalhada do Portainer |
| **7** | [07-Governanca-Git.md](./07-Governanca-Git.md) | Governança e boas práticas de Git |
| **8** | [08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md) | PostgreSQL multi-disco |
| **9** | [09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md) | MariaDB multi-disco |
| **10** | [10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md) | Servidor NFS para persistência |
| **11** | [11-Migracao-Storage-LVM-Thin.md](./11-Migracao-Storage-LVM-Thin.md) | Migração de storage |
| **12** | [12-Preparando-Melhor-seu-Proxmox.md](./12-Preparando-Melhor-seu-Proxmox.md) | Boas práticas de instalação |

---

## 🎯 Status

| Componente | Status |
|------------|--------|
| VMs | ✅ 6 (3 managers + 3 workers) |
| Docker | ✅ Instalado |
| Swarm | ⏳ A inicializar |
| Traefik | ⏳ A deployar |
| Portainer | ⏳ A deployar |

---

*Documentação do ambiente Docker Swarm.*
