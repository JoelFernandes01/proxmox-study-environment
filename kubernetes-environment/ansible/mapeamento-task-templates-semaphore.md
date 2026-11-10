# Mapeamento de Task Templates para o Ansible Semaphore

Este documento serve como guia de referência para cadastrar ou atualizar os **Task Templates** no Ansible Semaphore, alinhado à nova estrutura sequencial de playbooks (00 a 16).

---

## 🚀 Esteira Sequencial de Implantação (00 a 16)

| Nº | Nome do Template no Semaphore | Caminho da Playbook (`Playbook Filename`) | Inventário | Repositório |
| :--- | :--- | :--- | :--- | :--- |
| **00** | `00 - Prepara Sistema Operacional` | `playbooks/00-base/00-prepara-so.yml` | K8s Inventory | k8s-playbooks |
| **01** | `01 - Configura Servidor NFS` | `playbooks/01-storage/01-configura-nfs-server.yml` | K8s Inventory | k8s-playbooks |
| **02** | `02 - Configura Keepalived (VIP)` | `playbooks/02-loadbalancer/02-configura-keepalived.yml` | K8s Inventory | k8s-playbooks |
| **03** | `03 - Configura HAProxy (LB 6443)` | `playbooks/02-loadbalancer/03-configura-haproxy.yml` | K8s Inventory | k8s-playbooks |
| **04** | `04 - Prepara Prereqs Kubernetes` | `playbooks/03-kubernetes/04-prepara-k8s-prereqs.yml` | K8s Inventory | k8s-playbooks |
| **05** | `05 - Init Control Plane 01` | `playbooks/03-kubernetes/05-init-control-plane-01.yml` | K8s Inventory | k8s-playbooks |
| **06** | `06 - Gera Tokens e Upload Certs` | `playbooks/03-kubernetes/06-gera-tokens-join.yml` | K8s Inventory | k8s-playbooks |
| **07** | `07 - Join Control Planes Secundarios` | `playbooks/03-kubernetes/07-join-control-planes.yml` | K8s Inventory | k8s-playbooks |
| **08** | `08 - Join Worker Nodes` | `playbooks/03-kubernetes/08-join-workers.yml` | K8s Inventory | k8s-playbooks |
| **09** | `09 - Instala CNI Calico` | `playbooks/03-kubernetes/09-instala-cni-calico.yml` | K8s Inventory | k8s-playbooks |
| **10** | `10 - Instala NFS Provisioner` | `playbooks/03-kubernetes/10-instala-nfs-provisioner.yml` | K8s Inventory | k8s-playbooks |
| **11** | `11 - Instala Metrics Server` | `playbooks/03-kubernetes/11-instala-metrics-server.yml` | K8s Inventory | k8s-playbooks |
| **12** | `12 - Instala MetalLB` | `playbooks/03-kubernetes/12-instala-metallb.yml` | K8s Inventory | k8s-playbooks |
| **13** | `13 - Instala Traefik Ingress` | `playbooks/03-kubernetes/13-instala-traefik-ingress.yml` | K8s Inventory | k8s-playbooks |
| **14** | `14 - Instala Cert-Manager` | `playbooks/03-kubernetes/14-instala-cert-manager.yml` | K8s Inventory | k8s-playbooks |
| **15** | `15 - Configura ClusterIssuer CA` | `playbooks/03-kubernetes/15-configura-cluster-issuer-ca.yml` | K8s Inventory | k8s-playbooks |
| **16** | `16 - Teste Aplicacao HTTPS` | `playbooks/03-kubernetes/16-deploy-aplicacao-teste-https.yml` | K8s Inventory | k8s-playbooks |

---

## ⚡ Template Mestre (Execução em 1 Clique)

Para rodar todo o provisionamento sequencial automaticamente do inicio ao fim:

| Nome do Template no Semaphore | Caminho da Playbook (`Playbook Filename`) | Inventário | Repositório |
| :--- | :--- | :--- | :--- |
| `00 - Esteira Completa (site.yml)` | `site.yml` | K8s Inventory | k8s-playbooks |

---

## 🛠️ Tarefas de Operações e Manutenção (`04-management`)

Tarefas fora da esteira de instalação para uso em "Day-2 Operations":

| Nome do Template no Semaphore | Caminho da Playbook (`Playbook Filename`) | Inventário | Repositório |
| :--- | :--- | :--- | :--- |
| `OPS - Reboot VMs` | `playbooks/04-management/ops-reboot-vms.yml` | K8s Inventory | k8s-playbooks |
| `OPS - Shutdown VMs` | `playbooks/04-management/ops-shutdown-vms.yml` | K8s Inventory | k8s-playbooks |
| `OPS - Verifica Cluster` | `playbooks/04-management/ops-verifica-cluster.yml` | K8s Inventory | k8s-playbooks |
