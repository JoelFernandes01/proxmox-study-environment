### 🛡 Doc 10 — Governança Git e Proteção de Credenciais em IaC/K8s
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Definir os padrões de governança, higiene de repositório, convenção de commits e segurança contra vazamento de segredos no repositório do ambiente.  
**Público:** Desenvolvedores, Engenheiros DevOps e SysAdmins.

---

#### 📋 Sumário
1. [Por Que Governança Importa em Repositórios de Infraestrutura](#1-por-que-governança-importa)
2. [Checklist Pré-Push Obrigatório](#2-checklist-pré-push-obrigatório)
3. [.gitignore Recomendado](#3-gitignore-recomendado)
4. [Convenção de Commits (Conventional Commits)](#4-convenção-de-commits)
5. [Procedimento em Caso de Vazamento de Segredos](#5-procedimento-em-caso-de-vazamento)

---

#### 1. Por Que Governança Importa
Repositórios de IaC (Terraform, Ansible e K8s manifests) contêm informações altamente sensíveis:
- Configurações `admin.conf` e `kubeconfig` (acesso total de admin ao cluster).
- Arquivos de estado `.tfstate` contendo tokens Proxmox e parâmetros em texto puro.
- Chaves privadas SSH e segredos do Ansible Vault.

---

#### 2. Checklist Pré-Push Obrigatório
Antes de executar `git push`, verifique:
- [ ] O arquivo `admin.conf` ou `kubeconfig` NÃO está sendo adicionado ao commit.
- [ ] O arquivo `terraform.tfstate` ou `terraform.tfvars` NÃO foi incluído.
- [ ] Nenhuma chave SSH privada (`id_rsa`, `id_terraform`) está no diff (`git diff --staged`).

---

#### 3. `.gitignore` Recomendado

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example

# Kubernetes / Helm
admin.conf
kubeconfig
config
*.kube/config

# Ansible
*.retry
.vault_pass

# Chaves e Certificados
*.pem
*.key
*.crt
*.pub
```

---

#### 4. Convenção de Commits

Seguimos o padrão **Conventional Commits**:
- `feat(k8s)`: Adiciona novo playbook ou manifest.
- `fix(terraform)`: Corrige timeouts na criação de VMs.
- `docs(readme)`: Atualiza documentação do repositório.

---

- **Próximo Passo**: **[11-Operacoes-Backup-DR.md](./11-Operacoes-Backup-DR.md)**.
