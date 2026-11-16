# Guia Definitivo da Esteira Sequencial de Automação Kubernetes HA

Este documento estabelece o **Manual Operacional e Arquitetural da Esteira de Automação Ansible** organizada por subdiretórios funcionais para implantação, orquestração e gestão contínua de um cluster Kubernetes de Alta Disponibilidade (HA) sobre Proxmox VE.

---

## 1. Estrutura de Diretórios e Sequenciamento de Execução

A arquitetura do repositório foi reestruturada por fases lógicas de infraestrutura, garantindo modularidade, facilidade de manutenção e rastreabilidade na esteira de CI/CD (Ansible Semaphore).

```text
playbooks/
├── 00-base/
│   └── 00-prepara-so.yml
├── 01-storage/
│   └── 01-configura-nfs-server.yml
├── 02-loadbalancer/
│   ├── 02-configura-keepalived.yml
│   └── 03-configura-haproxy.yml
├── 03-kubernetes/
│   ├── 04-prepara-k8s-prereqs.yml
│   ├── 05-init-control-plane-01.yml
│   ├── 06-gera-tokens-join.yml
│   ├── 07-join-control-planes.yml
│   └── 08-join-workers.yml
├── 04-network-storage/
│   ├── 09-instala-cni-calico.yml
│   └── 10-instala-nfs-provisioner.yml
├── 05-tools/
│   ├── 11-instala-portainer-agent.yml
│   ├── 12-instala-metallb.yml
│   ├── 13-instala-metrics-server.yml
│   ├── 14-instala-traefik-ingress.yml
│   ├── 15-instala-cert-manager.yml
│   └── 16-configura-cluster-issuer-ca.yml
└── 06-testing/
    ├── 17-valida-cluster-k8s-e2e.yml
    ├── 18-deploy-aplicacao-teste-https.yml
    ├── ops-reboot-vms.yml
    ├── ops-shutdown-vms.yml
    └── ops-verifica-cluster.yml
```

---

## 2. Detalhamento Técnico das Fases e Playbooks

### Fase 00 — Base do Sistema Operacional (`playbooks/00-base/`)
* **`00-prepara-so.yml`**: Realiza o hardening inicial do sistema operacional Ubuntu 24.04 LTS em todas as VMs. Atualiza pacotes, desativa a memória Swap permanentemente (`swapoff -a` e `/etc/fstab`), carrega módulos de kernel indispensáveis (`overlay`, `br_netfilter`) e ajusta parâmetros sysctl para encaminhamento de pacotes IPv4.

### Fase 01 — Armazenamento Persistente (`playbooks/01-storage/`)
* **`01-configura-nfs-server.yml`**: Configura o nó de armazenamento dedicado (ou host NFS). Instala o pacote `nfs-kernel-server`, cria os diretórios de exportação com permissões adequadas e define o arquivo `/etc/exports` para servir volumes persistentes ao cluster K8s.

### Fase 02 — Load Balancer de Alta Disponibilidade (`playbooks/02-loadbalancer/`)
* **`02-configura-keepalived.yml`**: Instala e configura o Keepalived nos nós de balanceamento de carga, garantindo a gestão do IP Virtual de Alta Disponibilidade (VIP) com verificação automática de saúde (healthcheck).
* **`03-configura-haproxy.yml`**: Instala o HAProxy e configura o roteamento TCP na porta `6443` apontando para os 3 nós de Control Plane (`k8s-control-plane-01`, `02` e `03`), provendo um endpoint único e redundante para a API do Kubernetes.

### Fase 03 — Bootstrap e Expansão do Cluster Kubernetes (`playbooks/03-kubernetes/`)
* **`04-prepara-k8s-prereqs.yml`**: Instala o container runtime (`containerd`), configura o cgroup driver `systemd`, adiciona os repositórios oficiais do Kubernetes e instala os utilitários `kubelet`, `kubeadm` e `kubectl` com versão travada (*hold*).
* **`05-init-control-plane-01.yml`**: Executa o `kubeadm init` no primeiro nó master (`k8s-control-plane-01`) utilizando a flag `--control-plane-endpoint` apontando para o VIP do HAProxy e cria a chave de certificado do control plane (`--upload-certs`).
* **`06-gera-tokens-join.yml`**: Extrai e registra dinamicamente os tokens de adesão e os hashes `ca-cert-hash` necessários para a entrada de novos nós no cluster.
* **`07-join-control-planes.yml`**: Executa o `kubeadm join` nos nós `k8s-control-plane-02` e `k8s-control-plane-03`, estabelecendo o quórum de Alta Disponibilidade da pilha etcd.
* **`08-join-workers.yml`**: Executa o `kubeadm join` nos Worker Nodes (`k8s-worker-01`, `02` e `03`), expandindo a capacidade computacional de execução de workloads.

### Fase 04 — Rede Interna e Armazenamento Dinâmico K8s (`playbooks/04-network-storage/`)
* **`09-instala-cni-calico.yml`**: Aplica o plugin CNI Calico para prover conectividade Pod-to-Pod, alocação de IPs na subnet do cluster e suporte a Network Policies.
* **`10-instala-nfs-provisioner.yml`**: Implanta o `nfs-subdir-external-provisioner` configurando o `StorageClass` padrão (`nfs-client`), permitindo a alocação dinâmica de PersistentVolumeClaims (PVCs).

### Fase 05 — Ferramentas de Gerenciamento, Ingress e Infra-serviços (`playbooks/05-tools/`)
* **`11-instala-portainer-agent.yml`**: Configura o Namespace, RBAC, Headless Service (`portainer-agent-headless`) para descoberta interna de nós e DaemonSet do **Portainer Agent** escutando na porta `9001`.
* **`12-instala-metallb.yml`**: Implanta o MetalLB via manifesto/Helm e aplica as CRDs `IPAddressPool` e `L2Advertisement`, reservando um intervalo de IPs da rede local para serviços do tipo `LoadBalancer`.
* **`13-instala-metrics-server.yml`**: Instala o Metrics Server oficial com a flag `--kubelet-insecure-tls`, habilitando o comando `kubectl top` e o auto-escalonamento de Pods (HPA).
* **`14-instala-traefik-ingress.yml`**: Implanta o Traefik Ingress Controller como porta de entrada HTTP/HTTPS para as aplicações expostas no cluster.
* **`15-instala-cert-manager.yml`**: Implanta o Cert-Manager para automação do ciclo de vida de certificados X.509 e SSL/TLS no Kubernetes.
* **`16-configura-cluster-issuer-ca.yml`**: Configura o `ClusterIssuer` do Cert-Manager utilizando a Autoridade Certificadora (CA) privada do ambiente.

### Fase 06 — Testes, Validação e Operações (`playbooks/06-testing/`)
* **`17-valida-cluster-k8s-e2e.yml`**: Realiza a suíte de testes de validação da saúde dos nós, pods do sistema, disponibilidade do CNI, StorageClass e resolução DNS interna.
* **`18-deploy-aplicacao-teste-https.yml`**: Implanta uma aplicação web de teste vinculada ao Ingress do Traefik e Cert-Manager, validando o encadeamento completo de Ingress, DNS e SSL/TLS.
* **`ops-reboot-vms.yml`**: Playbook operacional para realizar a reinicialização ordenada de todo o ambiente (Workers -> Control Planes -> Load Balancers).
* **`ops-shutdown-vms.yml`**: Playbook operacional para desligamento seguro e gracioso de todo o laboratório.
* **`ops-verifica-cluster.yml`**: Playbook de checagem rápida de integridade dos nós e pods em tempo de execução.

---

## 3. Mapeamento de Task Templates no Ansible Semaphore

| Nº | Nome da Task Template no Semaphore | Caminho da Playbook (`Playbook Filename`) | Inventário |
|---|---|---|---|
| 00 | `00 - Preparação Base do SO` | `playbooks/00-base/00-prepara-so.yml` | Proxmox K8s |
| 01 | `01 - Configuração Servidor NFS` | `playbooks/01-storage/01-configura-nfs-server.yml` | Proxmox K8s |
| 02 | `02 - Configuração Keepalived VIP` | `playbooks/02-loadbalancer/02-configura-keepalived.yml` | Proxmox K8s |
| 03 | `03 - Configuração HAProxy Kube-API` | `playbooks/02-loadbalancer/03-configura-haproxy.yml` | Proxmox K8s |
| 04 | `04 - Pré-requisitos K8s & Runtimes` | `playbooks/03-kubernetes/04-prepara-k8s-prereqs.yml` | Proxmox K8s |
| 05 | `05 - Inicialização Control Plane 01` | `playbooks/03-kubernetes/05-init-control-plane-01.yml` | Proxmox K8s |
| 06 | `06 - Geração de Tokens de Join` | `playbooks/03-kubernetes/06-gera-tokens-join.yml` | Proxmox K8s |
| 07 | `07 - Join Control Planes Adicionais` | `playbooks/03-kubernetes/07-join-control-planes.yml` | Proxmox K8s |
| 08 | `08 - Join Worker Nodes` | `playbooks/03-kubernetes/08-join-workers.yml` | Proxmox K8s |
| 09 | `09 - Instalação CNI Calico` | `playbooks/04-network-storage/09-instala-cni-calico.yml` | Proxmox K8s |
| 10 | `10 - Instalação NFS Provisioner` | `playbooks/04-network-storage/10-instala-nfs-provisioner.yml` | Proxmox K8s |
| 11 | `11 - Instalação Portainer Agent` | `playbooks/05-tools/11-instala-portainer-agent.yml` | Proxmox K8s |
| 12 | `12 - Instalação MetalLB LoadBalancer` | `playbooks/05-tools/12-instala-metallb.yml` | Proxmox K8s |
| 13 | `13 - Instalação Metrics Server` | `playbooks/05-tools/13-instala-metrics-server.yml` | Proxmox K8s |
| 14 | `14 - Instalação Traefik Ingress` | `playbooks/05-tools/14-instala-traefik-ingress.yml` | Proxmox K8s |
| 15 | `15 - Instalação Cert-Manager` | `playbooks/05-tools/15-instala-cert-manager.yml` | Proxmox K8s |
| 16 | `16 - Configuração ClusterIssuer CA` | `playbooks/05-tools/16-configura-cluster-issuer-ca.yml` | Proxmox K8s |
| 17 | `17 - Validação E2E Cluster K8s` | `playbooks/06-testing/17-valida-cluster-k8s-e2e.yml` | Proxmox K8s |
| 18 | `18 - Deploy Aplicação Teste HTTPS` | `playbooks/06-testing/18-deploy-aplicacao-teste-https.yml` | Proxmox K8s |
| OPS | `OPS - Reboot Geral das VMs` | `playbooks/06-testing/ops-reboot-vms.yml` | Proxmox K8s |
| OPS | `OPS - Desligamento Geral das VMs` | `playbooks/06-testing/ops-shutdown-vms.yml` | Proxmox K8s |
| OPS | `OPS - Verificação de Integridade` | `playbooks/06-testing/ops-verifica-cluster.yml` | Proxmox K8s |

---

## 4. Instruções de Execução Completa

### Execução via Linha de Comando (CLI)

Para executar a orquestração completa em uma única instrução automatizada a partir do nó de gerência:

```bash
ansible-playbook -i inventory.yml site.yml
```

### Execução de uma Fase Específica

Para executar individualmente qualquer uma das fases, basta apontar para a playbook da etapa correspondente:

```bash
# Exemplo: Reinstalar apenas o Portainer Agent
ansible-playbook -i inventory.yml playbooks/05-tools/11-instala-portainer-agent.yml

# Exemplo: Executar a validação End-to-End do cluster
ansible-playbook -i inventory.yml playbooks/06-testing/17-valida-cluster-k8s-e2e.yml
```
