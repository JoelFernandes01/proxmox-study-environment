# Docker Swarm no Proxmox com Terraform

Stack Terraform para provisionar um cluster Docker Swarm (3 managers + 3 workers) no Proxmox VE usando o provider `bpg/proxmox` e cloud-init.

---

## 📋 Pré-requisitos

- Terraform >= 1.5.0 instalado
- Acesso à API do Proxmox VE (token criado)
- Template de VM Ubuntu já criado no Proxmox (VM ID `8000`)
- Storage `storage-vms` disponível no nó `des`
- Bridge `vmbr0` configurada
- Rede `10.0.39.0/24` com gateway `10.0.39.1`
- Chave SSH pública gerada

---

## 📁 Estrutura de arquivos

```
/docker-swarm
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars
├── templates/
│   └── inventory.tpl
└── ansible/          (para uso futuro)
```

---

## 🌐 Topologia da stack

| Nome | Papel | IP | VM ID |
|---|---|---|---|
| docker-swarm-01 | manager | 10.0.39.100 | 9000 |
| docker-swarm-02 | manager | 10.0.39.101 | 9001 |
| docker-swarm-03 | manager | 10.0.39.102 | 9002 |
| docker-worker-01 | worker | 10.0.39.120 | 9010 |
| docker-worker-02 | worker | 10.0.39.121 | 9011 |
| docker-worker-03 | worker | 10.0.39.122 | 9012 |

Recursos por VM: **2 vCPU / 4 GB RAM / 50 GB disco**.

---

## 🚀 Passo a passo — provisionamento

### 1. Criar a estrutura de pastas

```bash
mkdir -p /docker-swarm/templates /docker-swarm/ansible
cd /docker-swarm
```

### 2. Criar os arquivos

Crie os arquivos `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `terraform.tfvars` e `templates/inventory.tpl` com o conteúdo desta stack.

### 3. Inicializar o Terraform

```bash
terraform init
```

### 4. Validar a configuração

```bash
terraform validate
```

### 5. Revisar o plano

```bash
terraform plan
```

### 6. Aplicar a stack (com paralelismo controlado)

⚠️ **IMPORTANTE**: O host Proxmox não aguenta criar 6 VMs em paralelo. Use `-parallelism=1` para criar **uma VM por vez**, evitando erros de timeout (`HTTP 596`).

**Opção A — Aplicar tudo de uma vez, sequencialmente:**

```bash
terraform apply -parallelism=1
```

**Opção B — Criar primeiro os 3 managers, depois os 3 workers (mais seguro):**

```bash
# Passo 1: Managers
terraform apply -parallelism=1 \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-01"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-02"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-03"]'

# Passo 2: Workers
terraform apply -parallelism=1 \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-01"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-02"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-03"]'

# Passo 3: Aplicar estado final (garante consistência)
terraform apply -parallelism=1
```

### 7. Verificar o resultado

```bash
terraform output docker_nodes_summary
```

Saída esperada:

```
{
  "docker-swarm-01"  = { ip = "10.0.39.100/24", role = "manager", vm_id = 9000 }
  "docker-swarm-02"  = { ip = "10.0.39.101/24", role = "manager", vm_id = 9001 }
  "docker-swarm-03"  = { ip = "10.0.39.102/24", role = "manager", vm_id = 9002 }
  "docker-worker-01" = { ip = "10.0.39.120/24", role = "worker",  vm_id = 9010 }
  "docker-worker-02" = { ip = "10.0.39.121/24", role = "worker",  vm_id = 9011 }
  "docker-worker-03" = { ip = "10.0.39.122/24", role = "worker",  vm_id = 9012 }
}
```

### 8. Gerar o inventário Ansible

```bash
terraform output -raw ansible_inventory > ansible/inventory.ini
cat ansible/inventory.ini
```

Saída esperada:

```ini
[managers]
docker-swarm-01 ansible_host=10.0.39.100 ansible_user=connect
docker-swarm-02 ansible_host=10.0.39.101 ansible_user=connect
docker-swarm-03 ansible_host=10.0.39.102 ansible_user=connect

[workers]
docker-worker-01 ansible_host=10.0.39.120 ansible_user=connect
docker-worker-02 ansible_host=10.0.39.121 ansible_user=connect
docker-worker-03 ansible_host=10.0.39.122 ansible_user=connect

[swarm:children]
managers
workers

[swarm:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### 9. Testar conectividade SSH com todas as VMs

```bash
for ip in 10.0.39.100 10.0.39.101 10.0.39.102 10.0.39.120 10.0.39.121 10.0.39.122; do
  echo "=== $ip ==="
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 connect@$ip "hostname && uptime"
done
```

---

## 🔧 Ajustes que foram necessários (lições aprendidas)

### 1. Timeouts no recurso da VM

O provider `bpg/proxmox` **não** aceita o bloco `timeouts {}` aninhado. Os timeouts são atributos diretos do recurso:

```hcl
resource "proxmox_virtual_environment_vm" "docker_environment" {
  # ...
  timeout_create  = 3600   # 60 min para criação
  timeout_clone   = 3600   # 60 min para clonagem
  timeout_migrate = 1800   # 30 min para updates (equivale ao "update")
  # ...
}
```

Atributos válidos: `timeout_create`, `timeout_clone`, `timeout_migrate`, `timeout_reboot`, `timeout_stop_vm`.

❌ `timeout_update` e `timeout_delete` **não existem**.

### 2. Paralelismo

Use **sempre** `-parallelism=1` no `apply`. O `pveproxy` do Proxmox tem um timeout interno de ~30s e clonagens paralelas causam `HTTP 596`.

### 3. Erro HTTP 596 (Connection timed out)

Esse erro vem do `pveproxy` do Proxmox, não do Terraform. Mitigações:
- Usar `-parallelism=1`
- Aumentar `timeout_clone` e `timeout_create` no recurso
- Se persistir, ajustar o timeout do `pveproxy` no Proxmox (`/usr/share/perl5/PVE/APIServer/AnyEvent.pm`) — **não recomendado em produção**

### 4. Variáveis não declaradas (warnings)

Se aparecer `Warning: Value for undeclared variable`, significa que o `terraform.tfvars` ainda tem variáveis antigas (`ubuntu_*`) que não existem mais no `variables.tf`. Solução: limpar o `tfvars`.

---

## 🧹 Como destruir o ambiente

```bash
terraform destroy -parallelism=1
```

Se quiser destruir VM por VM para não sobrecarregar o host:

```bash
# Destruir workers primeiro
terraform destroy -parallelism=1 \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-01"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-02"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-worker-03"]'

# Depois managers
terraform destroy -parallelism=1 \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-01"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-02"]' \
  -target='proxmox_virtual_environment_vm.docker_environment["docker-swarm-03"]'
```

---

## 🔁 Reconstruir o ambiente do zero (receita de bolo)

```bash
cd /docker-swarm

# 1. Destruir tudo (se já existir)
terraform destroy -parallelism=1 -auto-approve

# 2. Limpar state residual (opcional, se mudou algo estrutural)
rm -f terraform.tfstate terraform.tfstate.backup

# 3. Re-inicializar
terraform init -upgrade

# 4. Validar
terraform validate

# 5. Aplicar sequencialmente
terraform apply -parallelism=1 -auto-approve

# 6. Ver resultado
terraform output docker_nodes_summary

# 7. Gerar inventário Ansible
terraform output -raw ansible_inventory > ansible/inventory.ini
cat ansible/inventory.ini
```

---

## 🐳 Próximos passos (Ansible + Docker Swarm)

Com o inventário gerado em `ansible/inventory.ini`, o próximo passo é:

1. Criar `ansible/playbook.yml` para:
   - Instalar Docker em todas as 6 VMs
   - Inicializar o Swarm nos 3 managers
   - Fazer `docker swarm join` nos 3 workers
   - Fazer `docker swarm join-token manager` nos managers 02 e 03 (HA)

2. Executar:
   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
   ```

---

## 📌 Resumo dos comandos essenciais

| Ação | Comando |
|---|---|
| Inicializar | `terraform init` |
| Validar | `terraform validate` |
| Planejar | `terraform plan` |
| Aplicar (sequencial) | `terraform apply -parallelism=1` |
| Ver resumo | `terraform output docker_nodes_summary` |
| Gerar inventário | `terraform output -raw ansible_inventory > ansible/inventory.ini` |
| Destruir | `terraform destroy -parallelism=1` |

---

## 📚 Referências

- Provider: [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest)
- Documentação Docker Swarm: https://docs.docker.com/engine/swarm/
