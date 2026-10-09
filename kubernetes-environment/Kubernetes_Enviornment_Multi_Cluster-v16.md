# Kubernetes Environment Multi Cluster (Proxmox + Terraform + Ansible)

Documentação técnica completa e atualizada para o provisionamento e automação de um cluster Kubernetes em Alta Disponibilidade (HA) no Proxmox VE utilizando Terraform para infraestrutura como código (IaC) e Ansible para gerenciamento de configuração e armazenamento NFS.

---

## 📋 1. Visão Geral da Arquitetura

O ambiente foi projetado para alta disponibilidade, resiliência, facilidade de manutenção e armazenamento compartilhado. A topologia separa a camada de **balanceamento de carga (HAProxy + Keepalived)**, a camada de **orquestração (Control Planes)**, a camada de **processamento (Worker Nodes)** e a camada de **armazenamento dedicado (Servidor NFS)**.

```
                  [ Virtual IP (VIP): 10.0.39.50:6443 ]
                  ( FQDN: k8s-vip.nverse.local )
                                  |
            +---------------------+---------------------+
            |                                           |
  [ k8s-haproxy-01 ]                         [ k8s-haproxy-02 ]
    (10.0.39.41)                                (10.0.39.42)
  Keepalived (MASTER)                       Keepalived (BACKUP)
            |                                           |
            +---------------------+---------------------+
                                  |
     +----------------------------+----------------------------+
     |                            |                            |
[ k8s-control-plane-01 ]   [ k8s-control-plane-02 ]   [ k8s-control-plane-03 ]
  (10.0.39.43)                (10.0.39.44)                (10.0.39.45)
  Primary CP                  Secondary CP                Secondary CP
     |                            |                            |
     +----------------------------+----------------------------+
                                  |
     +----------------------------+----------------------------+
     |                            |                            |
[ k8s-worker-01 ]          [ k8s-worker-02 ]          [ k8s-worker-03 ]
  (10.0.39.61)                (10.0.39.62)                (10.0.39.63)
                                  |
            +---------------------+---------------------+
            |                                           |
  [ k8s-nfs-01 ] (10.0.39.70)                 [ StorageClass ]
   Servidor NFS (PV/PVC)                      `nfs-client` (Default)
```

---

## 🌐 2. Topologia da Infraestrutura (Proxmox VE)

* **Subnet da Rede**: `10.0.39.0/24` (Gateway: `10.0.39.1`, Interface Bridge: `vmbr0`)
* **Endpoint da API do Kubernetes (VIP)**: `10.0.39.50:6443` (`k8s-vip.nverse.local`)
* **Domínio do Cluster**: `nverse.local`
* **Usuário SSH**: `connect` (com privilégio de elevação `sudo` sem senha)

| Nome da VM / Host | FQDN | Papel / Função | IP Estático | VM ID Proxmox | vCPU | RAM | Disco |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `k8s-vip` | `k8s-vip.nverse.local` | Virtual IP (Keepalived) | `10.0.39.50` | N/A (VIP) | - | - | - |
| `k8s-haproxy-01` | `k8s-haproxy-01.nverse.local` | Load Balancer / Keepalived Master | `10.0.39.41` | `9400` | 2 | 4 GB | 50 GB |
| `k8s-haproxy-02` | `k8s-haproxy-02.nverse.local` | Load Balancer / Keepalived Backup | `10.0.39.42` | `9401` | 2 | 4 GB | 50 GB |
| `k8s-control-plane-01` | `k8s-control-plane-01.nverse.local` | Control Plane Principal (Init) | `10.0.39.43` | `9402` | 2 | 4 GB | 50 GB |
| `k8s-control-plane-02` | `k8s-control-plane-02.nverse.local` | Control Plane Secundário | `10.0.39.44` | `9403` | 2 | 4 GB | 50 GB |
| `k8s-control-plane-03` | `k8s-control-plane-03.nverse.local` | Control Plane Secundário | `10.0.39.45` | `9404` | 2 | 4 GB | 50 GB |
| `k8s-worker-01` | `k8s-worker-01.nverse.local` | Worker Node | `10.0.39.61` | `9405` | 2 | 4 GB | 50 GB |
| `k8s-worker-02` | `k8s-worker-02.nverse.local` | Worker Node | `10.0.39.62` | `9406` | 2 | 4 GB | 50 GB |
| `k8s-worker-03` | `k8s-worker-03.nverse.local` | Worker Node | `10.0.39.63` | `9407` | 2 | 4 GB | 50 GB |
| `k8s-nfs-01` | `k8s-nfs-01.nverse.local` | Servidor NFS (Storage Compartilhado) | `10.0.39.70` | `9408` | 2 | 2 GB | 100 GB |

---

## 🚀 3. Etapa 1: Provisionamento com Terraform

O Terraform utiliza o provider `bpg/proxmox` para clonar o template Ubuntu Cloud-Init (`VM ID 8000`) e configurar dinamicamente redes, recursos, discos e chaves SSH.

### A. Execução Geral (Simultânea)
```bash
terraform init
terraform validate
terraform apply -parallelism=1 -auto-approve
```

### B. Provisionamento por Etapas Sequenciais (Recomendado)
Para evitar gargalos de I/O de disco no Proxmox durante a clonagem das 9 VMs Cloud-Init, recomenda-se criar o ambiente de forma gradativa:

#### 1. Servidor NFS (`k8s-nfs-01`)
```bash
terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-nfs-01"]' -parallelism=1 -auto-approve
```

#### 2. Control Planes (`k8s-control-plane-01` a `03`)
```bash
terraform apply   -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-01"]'   -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-02"]'   -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-03"]'   -parallelism=1 -auto-approve
```

#### 3. Worker Nodes (`k8s-worker-01` a `03`)
```bash
terraform apply   -target='proxmox_virtual_environment_vm.k8s["k8s-worker-01"]'   -target='proxmox_virtual_environment_vm.k8s["k8s-worker-02"]'   -target='proxmox_virtual_environment_vm.k8s["k8s-worker-03"]'   -parallelism=1 -auto-approve
```

#### 4. Load Balancers / HAProxy (`k8s-haproxy-01` e `02`)
```bash
terraform apply   -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-01"]'   -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-02"]'   -parallelism=1 -auto-approve
```

#### 5. Consolidação Geral e Inventário Ansible
```bash
terraform apply -parallelism=1 -auto-approve
```

### C. Resultado Final da Execução do Terraform (Outputs)
```text
Apply complete! Resources: 2 added, 0 changed, 1 destroyed.

Outputs:

k8s_control_planes_ips = {
  "k8s-control-plane-01" = "10.0.39.43/24"
  "k8s-control-plane-02" = "10.0.39.44/24"
  "k8s-control-plane-03" = "10.0.39.45/24"
}
k8s_haproxy_ips = {
  "k8s-haproxy-01" = "10.0.39.41/24"
  "k8s-haproxy-02" = "10.0.39.42/24"
}
k8s_nfs_ips = {
  "k8s-nfs-01" = "10.0.39.70/24"
}
k8s_nodes_summary = {
  "k8s-control-plane-01" = {
    "ip" = "10.0.39.43/24"
    "role" = "control-plane"
    "vm_id" = 9402
  }
  "k8s-control-plane-02" = {
    "ip" = "10.0.39.44/24"
    "role" = "control-plane"
    "vm_id" = 9403
  }
  "k8s-control-plane-03" = {
    "ip" = "10.0.39.44/24"
    "role" = "control-plane"
    "vm_id" = 9404
  }
  "k8s-haproxy-01" = {
    "ip" = "10.0.39.41/24"
    "role" = "haproxy"
    "vm_id" = 9400
  }
  "k8s-haproxy-02" = {
    "ip" = "10.0.39.42/24"
    "role" = "haproxy"
    "vm_id" = 9401
  }
  "k8s-nfs-01" = {
    "ip" = "10.0.39.70/24"
    "role" = "nfs"
    "vm_id" = 9408
  }
  "k8s-worker-01" = {
    "ip" = "10.0.39.61/24"
    "role" = "worker"
    "vm_id" = 9405
  }
  "k8s-worker-02" = {
    "ip" = "10.0.39.62/24"
    "role" = "worker"
    "vm_id" = 9406
  }
  "k8s-worker-03" = {
    "ip" = "10.0.39.63/24"
    "role" = "worker"
    "vm_id" = 9407
  }
}
k8s_workers_ips = {
  "k8s-worker-01" = "10.0.39.61/24"
  "k8s-worker-02" = "10.0.39.62/24"
  "k8s-worker-03" = "10.0.39.63/24"
}
```

---

## 📁 4. Organização de Arquivos do Ansible

### A. Estrutura Final do Diretório `ansible/`
```text
ansible/
├── ansible.cfg
├── inventory.yml
├── site.yml
└── playbooks/
    ├── base/
    │   └── 00-prepara-so.yml
    ├── storage/
    │   └── 01-configura-nfs-server.yml
    ├── keepalived/
    │   └── 02-configura-keepalived.yml
    ├── loadbalancer/
    │   └── 03-configura-haproxy.yml
    ├── kubernetes/
    │   ├── 01-prepara-k8s-prereqs.yml
    │   ├── 04-init-control-plane-01.yml
    │   ├── 05-gera-tokens-join.yml
    │   ├── 06-join-control-planes.yml
    │   ├── 07-join-workers.yml
    │   ├── 08-instala-cni-calico.yml
    │   └── 09-instala-nfs-provisioner.yml
    └── management/
        ├── 10-reboot-vms.yml
        ├── 11-shutdown-vms.yml
        └── 12-verifica-cluster.yml
```

---

## ⚙️ 5. Teste de Conectividade do Ansible (`ansible all -m ping`)

Validação de comunicação SSH em todos os 9 nós do ambiente:

```bash
ansible all -i inventory.yml -m ping
```

### Resultado do Comando:
```text
k8s-nfs-01           | SUCCESS => { "changed": false, "ping": "pong" }
k8s-control-plane-03 | SUCCESS => { "changed": false, "ping": "pong" }
k8s-control-plane-01 | SUCCESS => { "changed": false, "ping": "pong" }
k8s-haproxy-01       | SUCCESS => { "changed": false, "ping": "pong" }
k8s-haproxy-02       | SUCCESS => { "changed": false, "ping": "pong" }
k8s-control-plane-02 | SUCCESS => { "changed": false, "ping": "pong" }
k8s-worker-01        | SUCCESS => { "changed": false, "ping": "pong" }
k8s-worker-02        | SUCCESS => { "changed": false, "ping": "pong" }
k8s-worker-03        | SUCCESS => { "changed": false, "ping": "pong" }
```

---

## 📜 6. Execução da Esteira Automatizada (`ansible-playbook site.yml`)

### A. Estrutura do Orquestrador (`ansible/site.yml`)
```yaml
---
# =========================================================================
# Playbook Mestre — Esteira Completa do Cluster K8s HA (com Storage NFS)
# =========================================================================

- import_playbook: playbooks/base/00-prepara-so.yml
- import_playbook: playbooks/storage/01-configura-nfs-server.yml
- import_playbook: playbooks/kubernetes/01-prepara-k8s-prereqs.yml
- import_playbook: playbooks/keepalived/02-configura-keepalived.yml
- import_playbook: playbooks/loadbalancer/03-configura-haproxy.yml
- import_playbook: playbooks/kubernetes/04-init-control-plane-01.yml
- import_playbook: playbooks/kubernetes/05-gera-tokens-join.yml
- import_playbook: playbooks/kubernetes/06-join-control-planes.yml
- import_playbook: playbooks/kubernetes/07-join-workers.yml
- import_playbook: playbooks/kubernetes/08-instala-cni-calico.yml
- import_playbook: playbooks/kubernetes/09-instala-nfs-provisioner.yml
- import_playbook: playbooks/management/12-verifica-cluster.yml
```

### B. Execução do Playbook
```bash
ansible-playbook site.yml
```

### C. Resultado do PLAY RECAP (Execução Completa do Cluster + NFS):
```text
PLAY RECAP ****************************************************************************************************
k8s-control-plane-01       : ok=43   changed=27   unreachable=0    failed=0    skipped=2    rescued=0    ignored=0   
k8s-control-plane-02       : ok=24   changed=19   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-control-plane-03       : ok=24   changed=19   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-haproxy-01             : ok=29   changed=22   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-haproxy-02             : ok=29   changed=22   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-nfs-01                 : ok=20   changed=16   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-worker-01              : ok=22   changed=17   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-worker-02              : ok=22   changed=17   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
k8s-worker-03              : ok=22   changed=17   unreachable=0    failed=0    skipped=1    rescued=0    ignored=0 
```

---

## 🔑 7. Configuração e Cópia do Arquivo de Credenciais (`admin.conf`)

### A. Copiar credencial `admin.conf` para o host local

Para garantir a cópia e configuração correta do arquivo de credenciais no seu computador local (evitando erros de diretório inexistente):

```bash
# 1. Criar o diretório .kube na máquina local
mkdir -p ~/.kube

# 2. Copiar o arquivo de credenciais do Control Plane via SSH
ssh -i ~/.ssh/id_terraform connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config

# 3. Ajustar as permissões de segurança do arquivo de configuração
chmod 600 ~/.kube/config

# 4. Validar a conexão com o cluster
kubectl get no
```

### B. Mapear o FQDN no `/etc/hosts` da máquina local
```bash
echo "10.0.39.50 k8s-vip.nverse.local" | sudo tee -a /etc/hosts
```

### C. Validação Direta do Cluster via `kubectl get no`
```bash
❯ kubectl get no
```

**Resultado do Comando:**
```text
NAME                   STATUS   ROLES           AGE   VERSION
k8s-control-plane-01   Ready    control-plane   24m   v1.30.14
k8s-control-plane-02   Ready    control-plane   21m   v1.30.14
k8s-control-plane-03   Ready    control-plane   21m   v1.30.14
k8s-worker-01          Ready    <none>          20m   v1.30.14
k8s-worker-02          Ready    <none>          20m   v1.30.14
k8s-worker-03          Ready    <none>          20m   v1.30.14
```

### D. Validação da StorageClass Padrão (`kubectl get sc`)
```bash
❯ kubectl get sc
```

**Resultado Esperado:**
```text
NAME                   PROVISIONER                                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
nfs-client (default)   k8s-sigs.io/nfs-subdir-external-provisioner   Delete          Immediate           true                   2m
```

### E. Rotulagem dos Nós do Cluster (Labels e Roles)

#### 1. Rotulagem dos Worker Nodes:
```bash
kubectl label node k8s-worker-01 node-role.kubernetes.io/k8s-worker-01=
kubectl label node k8s-worker-02 node-role.kubernetes.io/k8s-worker-02=
kubectl label node k8s-worker-03 node-role.kubernetes.io/k8s-worker-03=
```

#### 2. Rotulagem Específica dos Control Planes (Opcional):
```bash
kubectl label node k8s-control-plane-01 node-role.kubernetes.io/control-plane-01=
kubectl label node k8s-control-plane-02 node-role.kubernetes.io/control-plane-02=
kubectl label node k8s-control-plane-03 node-role.kubernetes.io/control-plane-03=
```

---

## 🛠️ 8. Operações de Dia 2 (Day-2 Operations) & Ecossistema Helm

### A. Ferramental da Estação Local (Ubuntu)
* **Helm CLI**: Versão v4.1.0 (Client-side).
* **K9s**: Terminal UI interativo para visualização em tempo real de Pods e Métricas.
* **Kubectx & Kubens**: Alternância rápida de contexto e namespaces.

### B. Mapeamento dos Charts do Helm para Implantação do Ecossistema DevOps

| Camada | Ferramenta / Serviço | Chart Repository / Namespace | Função e Aplicação |
| :--- | :--- | :--- | :--- |
| **Camada 1** | `ingress-nginx` / `traefik` | `ingress-nginx` / `traefik` | Roteamento HTTP/HTTPS e Ingress Controller |
| **Camada 1** | `metallb` | `metallb` | Alocação de IPs virtuais para serviços LoadBalancer |
| **Camada 1** | `nfs-subdir-external-provisioner` | `nfs-subdir-external-provisioner` | Provedor dinâmico de StorageClass (`nfs-client`) |
| **Camada 1** | `cert-manager` | `jetstack` | Gerenciamento de certificados SSL/TLS |
| **Camada 2** | `gitea` | `gitea` / `gitea-charts` | Repositório Git auto-hospedado privado |
| **Camada 2** | `harbor` | `harbor` | Registro privado de Imagens OCI e Helm Charts |
| **Camada 2** | `argo-cd` | `argo` | Gerenciador de GitOps e Entrega Contínua |
| **Camada 3** | `jenkins` | `jenkins` | Servidor de automação CI/CD |
| **Camada 3** | `sonarqube` | `sonarqube` | Plataforma de inspeção contínua e qualidade de código |

---

## 💾 9. Estratégia de Backup e Disaster Recovery (DR)

### A. Backup do Estado do Cluster (etcd)
Execute o backup do banco de dados etcd no nó principal control plane:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snapshot-$(date +%Y%m%d).db
```

### B. Snapshots da Infraestrutura Proxmox VE (PBS)
* **Rotina Recomendada**: Snapshots diários das VMs de infraestrutura (IDs `9400` a `9408`).
* **Modo de Backup**: Snapshot a quente (sem indisponibilidade do cluster e do NFS).

---

## 📌 10. Resumo de Comandos Essenciais

| Ação | Comando |
| :--- | :--- |
| **Provisionar Infraestrutura Geral (Terraform)** | `terraform apply -parallelism=1 -auto-approve` |
| **Provisionar Etapa 1: NFS** | `terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-nfs-01"]' -parallelism=1 -auto-approve` |
| **Provisionar Etapa 2: Control Planes** | `terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-01"]' -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-02"]' -target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-03"]' -parallelism=1 -auto-approve` |
| **Provisionar Etapa 3: Workers** | `terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-worker-01"]' -target='proxmox_virtual_environment_vm.k8s["k8s-worker-02"]' -target='proxmox_virtual_environment_vm.k8s["k8s-worker-03"]' -parallelism=1 -auto-approve` |
| **Provisionar Etapa 4: HAProxy** | `terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-01"]' -target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-02"]' -parallelism=1 -auto-approve` |
| **Testar Conectividade SSH (Ansible)** | `ansible all -i inventory.yml -m ping` |
| **Executar Esteira Completa (Ansible)** | `ansible-playbook site.yml` *(dentro da pasta ansible/)* |
| **Verificar Status do Cluster (Ansible)** | `ansible-playbook playbooks/management/12-verifica-cluster.yml` |
| **Copiar Credencial Localmente** | `mkdir -p ~/.kube && ssh -i ~/.ssh/id_terraform connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config && chmod 600 ~/.kube/config` |
| **Validar Nós do Host Local** | `kubectl get no` |
| **Validar StorageClass NFS** | `kubectl get sc` |
| **Destruir Infraestrutura** | `terraform destroy -parallelism=1 -auto-approve` |
