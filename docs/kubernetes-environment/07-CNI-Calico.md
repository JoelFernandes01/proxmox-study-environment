### 🌐 Doc 7 — Plugin de Rede Pod CNI Calico
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a instalação, configuração e validação do plugin CNI Calico para prover conectividade Pod-to-Pod L3 e controle de políticas de rede no cluster Kubernetes.  
**Pré-requisito:** Cluster inicializado via `kubeadm` (**Doc 5**).

---

#### 📋 Sumário
1. [Por Que Calico CNI?](#1-por-que-calico-cni)
2. [Instalação via Manifests (Tigera Operator)](#2-instalação-via-manifests-tigera-operator)
3. [Configuração do Pod CIDR (`192.168.0.0/16`)](#3-configuração-do-pod-cidr-1921680016)
4. [Playbook Ansible (`08-instala-cni-calico.yml`)](#4-playbook-ansible-08-instala-cni-calico)
5. [Validação de Conectividade Pod-to-Pod](#5-validação-de-conectividade-pod-to-pod)

---

#### 1. Por Que Calico CNI?
- **Desempenho L3**: Utiliza roteamento IP nativo (BGP/VXLAN) sem overhead desnecessário de encapsulamento.
- **Network Policies**: Suporte completo ao objeto `NetworkPolicy` para microsegmentação de segurança.

---

#### 2. Instalação via Manifests (Tigera Operator)

```bash
# 1. Instalar Tigera Operator e Custom Resources do Calico
kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
```

---

#### 3. Playbook Ansible (`playbooks/kubernetes/08-instala-cni-calico.yml`)

```yaml
---
- name: 08 - Instala CNI Calico
  hosts: k8s-control-plane-01
  become: yes
  tasks:
    - name: Aplica Tigera Operator
      command: kubectl create -f tigera-operator.yaml
      register: calico_op
      failed_when:
        - calico_op.rc != 0
        - "'already exists' not in calico_op.stderr"

    - name: Aplica Custom Resources do Calico
      command: kubectl create -f custom-resources.yaml
      register: calico_cr
      failed_when:
        - calico_cr.rc != 0
        - "'already exists' not in calico_cr.stderr"
```

---

#### 4. Validação do Status dos Nós

Após a instalação do CNI, todos os nós devem migrar para o estado **Ready**:

```bash
kubectl get nodes
```

##### Saída Esperada:
```
NAME                   STATUS   ROLES           AGE   VERSION
k8s-control-plane-01   Ready    control-plane   25m   v1.30.14
k8s-control-plane-02   Ready    control-plane   22m   v1.30.14
k8s-control-plane-03   Ready    control-plane   22m   v1.30.14
k8s-worker-01          Ready    <none>          20m   v1.30.14
k8s-worker-02          Ready    <none>          20m   v1.30.14
k8s-worker-03          Ready    <none>          20m   v1.30.14
```

---

- **Próximo Passo**: **[08-NFS-Server-StorageClass.md](./08-NFS-Server-StorageClass.md)**.
