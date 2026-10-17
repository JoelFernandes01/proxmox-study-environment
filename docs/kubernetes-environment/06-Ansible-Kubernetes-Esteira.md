### 🤖 Doc 6 — Automação da Esteira Completa do Cluster via Ansible
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a estrutura de playbooks e a execução orquestrada do Ansible (`site.yml`) que automatiza 100% da criação do ambiente Kubernetes HA, desde o SO até o CNI e Storage.  
**Pré-requisito:** VMs provisionadas (**Doc 2**), Ansible instalado na máquina de controle.

---

#### 📋 Sumário
1. [Estrutura Completa de Diretórios](#1-estrutura-completa-de-diretórios)
2. [Inventário Ansible (`inventory.yml`)](#2-inventário-ansible-inventoryyml)
3. [Playbook Orquestrador (`site.yml`)](#3-playbook-orquestrador-siteyml)
4. [Execução e Análise do PLAY RECAP](#4-execução-e-análise-do-play-recap)
5. [Playbooks de Gestão e Manutenção](#5-playbooks-de-gestão-e-manutenção)

---

#### 1. Estrutura Completa de Diretórios

```
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

#### 2. Inventário Ansible (`inventory.yml`)

```yaml
all:
  vars:
    ansible_user: connect
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  children:
    haproxy:
      hosts:
        k8s-haproxy-01: { ansible_host: 10.0.39.41 }
        k8s-haproxy-02: { ansible_host: 10.0.39.42 }
    control_planes:
      hosts:
        k8s-control-plane-01: { ansible_host: 10.0.39.43 }
        k8s-control-plane-02: { ansible_host: 10.0.39.44 }
        k8s-control-plane-03: { ansible_host: 10.0.39.45 }
    workers:
      hosts:
        k8s-worker-01: { ansible_host: 10.0.39.61 }
        k8s-worker-02: { ansible_host: 10.0.39.62 }
        k8s-worker-03: { ansible_host: 10.0.39.63 }
    nfs_server:
      hosts:
        k8s-nfs-01: { ansible_host: 10.0.39.70 }
```

---

#### 3. Playbook Orquestrador (`site.yml`)

```yaml
---
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

---

#### 4. Execução e Análise do PLAY RECAP

```bash
ansible-playbook -i inventory.yml site.yml
```

##### Exemplo de Resultado com Sucesso:
```
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

- **Próximo Passo**: **[07-CNI-Calico.md](./07-CNI-Calico.md)**.
