# Manual Operacional Definitivo: Recriação de Infraestrutura, Implantação do Kubernetes HA e Stack Zabbix 8.0 LTS

Este documento fornece o procedimento operacional padrão (SOP) completo para zerar, clonar, configurar e validar a infraestrutura de laboratório no **Proxmox VE**, a esteira de implantação do cluster **Kubernetes High Availability (Kubeadm + Keepalived + HAProxy + Calico CNI + MetalLB + Traefik + Cert-Manager)** e a stack de monitoramento do **Zabbix 8.0 LTS**.

---

## 📋 Sumário
1. [Ciclo de Vida das VMs no Proxmox VE](#1-ciclo-de-vida-das-vms-no-proxmox-ve)
2. [Configuração de Acesso SSH Sem Senha](#2-configuração-de-acesso-ssh-sem-senha)
3. [Matriz de Execução e Validação do Kubernetes HA](#3-matriz-de-execução-e-validação-do-kubernetes-ha)
4. [Matriz de Execução e Validação do Zabbix 8.0 LTS](#4-matriz-de-execução-e-validação-do-zabbix-80-lts)
5. [Plano de Contingência e Solução de Problemas (Troubleshooting)](#5-plano-de-contingência-e-solução-de-problemas-troubleshooting)

---

## 1. Ciclo de Vida das VMs no Proxmox VE

Quando for necessário zerar o ambiente para testes de implantação *End-to-End* (*Greenfield*), execute os comandos abaixo no nó do Proxmox VE (via CLI/PVE Shell).

### 1.1. Parada e Destruição das VMs Existentes
```bash
# Parar todas as VMs do cluster (IDs 101 a 106)
qm stop 101 && qm stop 102 && qm stop 103 && qm stop 104 && qm stop 105 && qm stop 106

# Destruir as VMs e seus discos associados
qm destroy 101 --purge && qm destroy 102 --purge && qm destroy 103 --purge
qm destroy 104 --purge && qm destroy 105 --purge && qm destroy 106 --purge
```

### 1.2. Clonagem a partir do Template Cloud-Init (ID 9000)
```bash
# Control Planes (101=k8s-control-plane-01, 102=k8s-control-plane-02, 103=k8s-control-plane-03)
qm clone 9000 101 --name k8s-control-plane-01 --full
qm clone 9000 102 --name k8s-control-plane-02 --full
qm clone 9000 103 --name k8s-control-plane-03 --full

# Worker Nodes (104=k8s-worker-01, 105=k8s-worker-02, 106=k8s-worker-03)
qm clone 9000 104 --name k8s-worker-01 --full
qm clone 9000 105 --name k8s-worker-02 --full
qm clone 9000 106 --name k8s-worker-03 --full
```

### 1.3. Ajuste de Recursos e Inicialização
```bash
# Configurar CPU e Memória para os Control Planes (4 vCPUs, 4GB RAM)
for id in 101 102 103; do
  qm set $id --cores 4 --memory 4096
done

# Configurar CPU e Memória para os Workers (4 vCPUs, 6GB RAM)
for id in 104 105 106; do
  qm set $id --cores 4 --memory 6144
done

# Iniciar todas as VMs
qm start 101 && qm start 102 && qm start 103
qm start 104 && qm start 105 && qm start 106
```

---

## 2. Configuração de Acesso SSH Sem Senha

Na máquina onde o Ansible Semaphore ou CLI executa as playbooks:

```bash
# 1. Gerar par de chaves SSH (caso ainda não exista)
ssh-keygen -t ed25519 -C "ansible-deploy" -N "" -f ~/.ssh/id_ed25519

# 2. Copiar a chave pública para todas as VMs (Usuário: connect)
for ip in 10.0.39.43 10.0.39.44 10.0.39.45 10.0.39.47 10.0.39.48 10.0.39.49; do
  ssh-copy-id -o StrictHostKeyChecking=no connect@$ip
done

# 3. Teste de conectividade Ansible sem senha
ansible all -i production.ini -m ping
```
* **Resultado Esperado**: Todas as 6 instâncias respondendo `pong` em verde (`SUCCESS`).

---

## 3. Matriz de Execução e Validação do Kubernetes HA

Executar as playbooks do repositório `k8s-playbooks` na ordem estrita definida abaixo.

### 📍 Playbook 04: `04-prepara-k8s-prereqs.yml`
* **Objetivo**: Desativar Swap, carregar módulos de rede do kernel (`overlay`, `br_netfilter`), ajustar sysctl e instalar `containerd`/`kubelet`/`kubeadm`.
* **Comandos de Validação**:
  ```bash
  ansible all -i production.ini -a "swapon -s" --become
  ansible all -i production.ini -a "systemctl is-active containerd" --become
  ```
* **Critério de Sucesso**: Saída do `swapon` vazia e `containerd` retornando `active` em todas as VMs.

### 📍 Playbook 05: `05-init-control-plane-01.yml`
* **Objetivo**: Limpeza prévia do `etcd`/`kubeadm`, execução do `kubeadm init` com endpoint `10.0.39.50:6443` e criação do arquivo local resiliente `/etc/kubernetes/admin-local.conf` (`10.0.39.43:6443`).
* **Comandos de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ssh connect@10.0.39.43 "cat /etc/kubernetes/admin-local.conf | grep server"
  ```
* **Critério de Sucesso**: Nó `k8s-control-plane-01` visível e servidor apontando para `https://10.0.39.43:6443`.

### 📍 Playbook 06: `06-gera-tokens-join.yml`
* **Objetivo**: Gerar novo token de join e chave de criptografia de certificados (`--upload-certs`).
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubeadm token list"
  ```
* **Critério de Sucesso**: Token ativo listado com tempo de expiração válido.

### 📍 Playbook 07: `07-join-control-planes.yml`
* **Objetivo**: Limpar e adicionar `k8s-control-plane-02` (`.44`) e `k8s-control-plane-03` (`.45`) ao plano de controle.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ```
* **Critério de Sucesso**: Os 3 nós de Control Plane listados (status `NotReady` até a instalação da CNI).

### 📍 Playbook 08: `08-join-workers.yml`
* **Objetivo**: Limpar e juntar os 3 Worker Nodes ao cluster.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ```
* **Critério de Sucesso**: Todos os 6 nós (3 CPs e 3 Workers) listados na saída.

### 📍 Playbook 09: `09-instala-cni-calico.yml`
* **Objetivo**: Implantar a CNI Calico conectando via `admin-local.conf` para habilitar a rede de Pods (CIDR `192.168.0.0/16`).
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n kube-system -l k8s-app=calico-node"
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ```
* **Critério de Sucesso**: 6 pods do `calico-node` em `1/1 Running` e **todos os 6 nós com status `Ready`**.

### 📍 Playbook 11: `11-instala-metrics-server.yml`
* **Objetivo**: Implantar o Metrics Server com a flag `--kubelet-insecure-tls`.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf top nodes"
  ```
* **Critério de Sucesso**: Métricas de consumo de CPU e Memória exibidas para os nós do cluster.

### 📍 Playbook 12: `12-instala-metallb.yml`
* **Objetivo**: Instalar o MetalLB v0.13.12 em modo L2 puro com o pool de IPs `10.0.39.200 - 10.0.39.250`.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n metallb-system"
  ```
* **Critério de Sucesso**: Pods do controller e speakers do MetalLB operando em estado `Running`.

### 📍 Playbook 13: `13-instala-traefik-ingress.yml`
* **Objetivo**: Implantar o Traefik Ingress Controller via Helm solicitando IP ao MetalLB.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get svc -n traefik traefik"
  ```
* **Critério de Sucesso**: Serviço do Traefik recebendo um IP EXTERNAL-IP válido da faixa do MetalLB (ex: `10.0.39.200`).

### 📍 Playbooks 14 e 15: `14-instala-cert-manager.yml` & `15-configura-cluster-issuer-ca.yml`
* **Objetivo**: Provisionar a infraestrutura de certificados TLS internos.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get clusterissuer"
  ```
* **Critério de Sucesso**: `ca-issuer` em estado `Ready: True`.

---

## 4. Matriz de Execução e Validação do Zabbix 8.0 LTS

Executar as playbooks do repositório `monitoring-environment`.

### 📍 Playbook 01: `01-configura-banco-zabbix.yml`
* **Objetivo**: Deploy do banco PostgreSQL 16 Alpine (`postgres:16-alpine`) e Secret `zabbix-db-secret` no namespace `zabbix`.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n zabbix -l app=zabbix-postgresql"
  ```
* **Critério de Sucesso**: Pod do PostgreSQL 16 em `1/1 Running`.

### 📍 Playbook 02: `02-deploy-zabbix-server.yml`
* **Objetivo**: Implantar Zabbix Server 8.0 LTS (`ubuntu-8.0-latest`), Zabbix Web UI Nginx (porta 8080) e expor o LoadBalancer `10.0.39.201`.
* **Comando de Validação**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get svc -n zabbix zabbix-web-service"
  curl -I http://10.0.39.201
  ```
* **Critério de Sucesso**: LoadBalancer no IP `10.0.39.201` e o `curl` retornando código HTTP `200 OK` ou `302 Found`.

### 📍 Playbook 03: `03-instala-zabbix-agents-vms.yml`
* **Objetivo**: Provisionar o `zabbix-agent2` (v8.0 LTS) nas VMs apontando para `10.0.39.201`.
* **Comando de Validação**:
  ```bash
  ansible all_vms -i production.ini -a "systemctl status zabbix-agent2" --become
  ```
* **Critério de Sucesso**: Serviço do agente ativo (`active (running)`) em todas as VMs.

---

## 5. Plano de Contingência e Solução de Problemas (Troubleshooting)

### ⚠️ Erro: `x509: certificate signed by unknown authority` no HAProxy
* **Causa**: Chamada do `kubectl` ou `helm` enviada para o VIP `10.0.39.50:6443` durante o balanceamento *Round-Robin* enquanto nós secundários ainda estão sincronizando.
* **Solução**: Garantir que a playbook está utilizando `--kubeconfig=/etc/kubernetes/admin-local.conf` (que força a conexão direta em `https://10.0.39.43:6443`).

### ⚠️ Erro: Pods do Calico em `Init:0/1` ou `CrashLoopBackOff`
* **Causa**: Restos de regras de rede de instalações anteriores do `iptables` ou interface `tunl0` residual.
* **Solução**:
  ```bash
  ansible all -i production.ini -m shell -a "ip link delete tunl0 || true; iptables -F && iptables -t nat -F" --become
  ```

---

*Manual gerado para o repositório proxmox-study-environment (Joel Fernandes).*
