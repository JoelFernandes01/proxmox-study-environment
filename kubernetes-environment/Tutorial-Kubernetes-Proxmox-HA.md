# Guia Definitivo: Cluster Kubernetes HA Multi-Node do Zero no Proxmox VE

Este tutorial fornece um passo a passo completo para arquitetar, provisionar e automatizar um cluster Kubernetes de Alta Disponibilidade (HA) multinó sobre o hipervisor Proxmox VE. A solução utiliza Infraestrutura como Código (IaC) com Terraform, Gestão de Configuração e Orquestração declarativa com Ansible e Ansible Semaphore, além do ecossistema completo de rede, armazenamento e segurança com MetalLB, Traefik Ingress Controller, Cert-Manager e NFS.

---

## 1. Arquitetura da Infraestrutura e Topologia de Rede

O cluster foi projetado para garantir resiliência contra falhas de hardware e isolamento de responsabilidades. O ponto de entrada da API do Kubernetes (`kube-apiserver`) é protegido por um IP Virtual (VIP) gerenciado por Keepalived e HAProxy, distribuindo as requisições na porta `6443` entre os nós do plano de controle.

### Mapeamento de IPs, Hosts e Funções

Toda a infraestrutura está alocada na sub-rede `10.0.39.0/24`.

| Hostname | Endereço IP | Papel / Função | Especificação Recomendada | Sistema Operacional |
| :--- | :--- | :--- | :--- | :--- |
| `k8s-haproxy-01` | `10.0.39.41` | Load Balancer Master (Keepalived + HAProxy) | 2 vCPU, 2 GB RAM, 20 GB Disk | Ubuntu 22.04 LTS |
| `k8s-haproxy-02` | `10.0.39.42` | Load Balancer Backup (Keepalived + HAProxy) | 2 vCPU, 2 GB RAM, 20 GB Disk | Ubuntu 22.04 LTS |
| `VIP (Virtual IP)` | `10.0.39.50` | IP Virtual Flutuante da API (Porta 6443) | Failover VRRP automático | Keepalived VRRP |
| `k8s-control-plane-01` | `10.0.39.51` | Control Plane 01 (Bootstrap / Kubeadm Init) | 2 vCPU, 4 GB RAM, 30 GB Disk | Ubuntu 22.04 LTS |
| `k8s-control-plane-02` | `10.0.39.52` | Control Plane 02 (Control Plane Secundário) | 2 vCPU, 4 GB RAM, 30 GB Disk | Ubuntu 22.04 LTS |
| `k8s-control-plane-03` | `10.0.39.53` | Control Plane 03 (Control Plane Secundário) | 2 vCPU, 4 GB RAM, 30 GB Disk | Ubuntu 22.04 LTS |
| `k8s-worker-01` | `10.0.39.61` | Worker Node 01 | 4 vCPU, 8 GB RAM, 50 GB Disk | Ubuntu 22.04 LTS |
| `k8s-worker-02` | `10.0.39.62` | Worker Node 02 | 4 vCPU, 8 GB RAM, 50 GB Disk | Ubuntu 22.04 LTS |
| `k8s-worker-03` | `10.0.39.63` | Worker Node 03 | 4 vCPU, 8 GB RAM, 50 GB Disk | Ubuntu 22.04 LTS |
| `nfs-server` | `10.0.39.30` | Servidor de Storage NFS Compartilhado | 2 vCPU, 4 GB RAM, 100 GB Disk | Ubuntu 22.04 LTS |
| `MetalLB Pool` | `10.0.39.200 - 10.0.39.250` | Pool de IPs estáticos para Ingress / LoadBalancer | Alocação Layer 2 dinâmica | Kubernetes CRD |

---

## 2. Preparação dos Templates e Provisionamento (Proxmox + Terraform)

### Passo 1: Template Ubuntu 22.04 com Cloud-Init
No terminal do Proxmox VE, execute o script para baixar a imagem cloud oficial e convertê-la em um Template reutilizável (ID 9000):

```bash
# Baixar imagem oficial Ubuntu Cloud 22.04 LTS
wget ubuntu-22.04-server-cloudimg-amd64.img

# Criar a VM base no Proxmox
qm create 9000 --name "ubuntu-2204-cloudinit-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Importar o disco para o storage local-lvm
qm importdisk 9000 ubuntu-22.04-server-cloudimg-amd64.img local-lvm

# Atribuir o disco e o drive de Cloud-Init
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0

# Converter a VM em Template
qm template 9000
```

### Passo 2: Estrutura do Inventário Ansible (`inventories/production.ini`)

```ini
[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3

[loadbalancers]
k8s-haproxy-01 ansible_host=10.0.39.41
k8s-haproxy-02 ansible_host=10.0.39.42

[nfs_servers]
nfs-server ansible_host=10.0.39.30

[k8s_control_planes]
k8s-control-plane-01 ansible_host=10.0.39.51
k8s-control-plane-02 ansible_host=10.0.39.52
k8s-control-plane-03 ansible_host=10.0.39.53

[k8s_workers]
k8s-worker-01 ansible_host=10.0.39.61
k8s-worker-02 ansible_host=10.0.39.62
k8s-worker-03 ansible_host=10.0.39.63

[k8s_cluster:children]
k8s_control_planes
k8s_workers
```

---

## 3. Estrutura de Diretórios do Repositório Git

A organização por números sequenciais (`00` a `16`) garante a previsibilidade de execução tanto via CLI quanto no Ansible Semaphore.

```text
proxmox-study-environment/
├── inventories/
│   └── production.ini
├── playbooks/
│   ├── 00-base/
│   │   └── 00-prepara-so.yml
│   ├── 01-storage/
│   │   └── 01-configura-nfs-server.yml
│   ├── 02-loadbalancer/
│   │   ├── 02-configura-keepalived.yml
│   │   └── 03-configura-haproxy.yml
│   ├── 03-kubernetes/
│   │   ├── 04-prepara-k8s-prereqs.yml
│   │   ├── 05-init-control-plane-01.yml
│   │   ├── 06-gera-tokens-join.yml
│   │   ├── 07-join-control-planes.yml
│   │   ├── 08-join-workers.yml
│   │   ├── 09-instala-cni-calico.yml
│   │   ├── 10-instala-nfs-provisioner.yml
│   │   ├── 11-instala-metrics-server.yml
│   │   ├── 12-instala-metallb.yml
│   │   ├── 13-instala-traefik-ingress.yml
│   │   ├── 14-instala-cert-manager.yml
│   │   ├── 15-configura-cluster-issuer-ca.yml
│   │   └── 16-deploy-aplicacao-teste-https.yml
│   └── 04-management/
│       ├── ops-reboot-vms.yml
│       ├── ops-shutdown-vms.yml
│       └── ops-verifica-cluster.yml
└── site.yml
```

---

## 4. Esteira de Playbooks Ansible (Etapa por Etapa)

### Playbook Mestre (`site.yml`)

```yaml
---
# =========================================================================
# Esteira Completa de Deploy do Cluster Kubernetes HA no Proxmox VE
# =========================================================================

- import_playbook: playbooks/00-base/00-prepara-so.yml
- import_playbook: playbooks/01-storage/01-configura-nfs-server.yml
- import_playbook: playbooks/02-loadbalancer/02-configura-keepalived.yml
- import_playbook: playbooks/02-loadbalancer/03-configura-haproxy.yml
- import_playbook: playbooks/03-kubernetes/04-prepara-k8s-prereqs.yml
- import_playbook: playbooks/03-kubernetes/05-init-control-plane-01.yml
- import_playbook: playbooks/03-kubernetes/06-gera-tokens-join.yml
- import_playbook: playbooks/03-kubernetes/07-join-control-planes.yml
- import_playbook: playbooks/03-kubernetes/08-join-workers.yml
- import_playbook: playbooks/03-kubernetes/09-instala-cni-calico.yml
- import_playbook: playbooks/03-kubernetes/10-instala-nfs-provisioner.yml
- import_playbook: playbooks/03-kubernetes/11-instala-metrics-server.yml
- import_playbook: playbooks/03-kubernetes/12-instala-metallb.yml
- import_playbook: playbooks/03-kubernetes/13-instala-traefik-ingress.yml
- import_playbook: playbooks/03-kubernetes/14-instala-cert-manager.yml
- import_playbook: playbooks/03-kubernetes/15-configura-cluster-issuer-ca.yml
- import_playbook: playbooks/03-kubernetes/16-deploy-aplicacao-teste-https.yml
```

### Playbook 00 — Preparação do Sistema Operacional (`00-prepara-so.yml`)
Desabilita o Swap permanentemente, ajusta fstab e carrega os módulos de kernel necessários para contêineres (`overlay` e `br_netfilter`).

```yaml
---
- name: 00 - Preparacao do Sistema Operacional Base
  hosts: all
  become: yes
  tasks:
    - name: Desativar Swap em tempo de execucao
      ansible.builtin.command: swapoff -a
      when: ansible_swaptotal_mb > 0

    - name: Remover entrada de Swap do fstab
      ansible.builtin.replace:
        path: /etc/fstab
        regexp: '^([^#].*?\sswap\s+sw\s+.*)$'
        replace: '# \1'

    - name: Carregar modulos do Kernel
      community.general.modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - overlay
        - br_netfilter

    - name: Configurar parametros sysctl para Kubernetes
      ansible.posix.sysctl:
        name: "{{ item.name }}"
        value: "{{ item.value }}"
        state: present
        reload: yes
      loop:
        - { name: 'net.bridge.bridge-nf-call-iptables', value: '1' }
        - { name: 'net.bridge.bridge-nf-call-ip6tables', value: '1' }
        - { name: 'net.ipv4.ip_forward', value: '1' }
```

### Playbook 05 — Inicialização do Cluster (`05-init-control-plane-01.yml`)
Inicializa o primeiro nó de Control Plane definindo a URL do VIP e o CIDR de Pods compatível com o Calico (`192.168.0.0/16`).

```yaml
---
- name: 05 - Inicializa o primeiro Control Plane (kubeadm init)
  hosts: k8s-control-plane-01
  become: yes
  vars:
    control_plane_endpoint: "10.0.39.50:6443"
    pod_network_cidr: "192.168.0.0/16"
  tasks:
    - name: Executar kubeadm init
      ansible.builtin.command: >
        kubeadm init
        --control-plane-endpoint="{{ control_plane_endpoint }}"
        --upload-certs
        --pod-network-cidr="{{ pod_network_cidr }}"
      args:
        creates: /etc/kubernetes/admin.conf

    - name: Criar diretorio .kube para o usuario ubuntu
      ansible.builtin.file:
        path: /home/ubuntu/.kube
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Copiar admin.conf para o diretorio do usuario
      ansible.builtin.copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/ubuntu/.kube/config
        remote_src: yes
        owner: ubuntu
        group: ubuntu
        mode: '0600'
```

### Playbook 08 — Adição de Worker Nodes com Idempotência (`08-join-workers.yml`)

```yaml
---
- name: Obter token de join no primeiro control-plane
  hosts: k8s-control-plane-01
  become: true
  gather_facts: false
  tasks:
    - name: Gerar comando de join para os workers
      ansible.builtin.command: kubeadm token create --print-join-command
      register: join_worker_cmd_output

    - name: Definir join_worker_cmd em memoria
      ansible.builtin.set_fact:
        join_worker_cmd: "{{ join_worker_cmd_output.stdout }}"

- name: Adicionar workers ao cluster
  hosts: k8s_workers
  become: true
  gather_facts: true
  tasks:
    - name: Executar kubeadm join para workers
      ansible.builtin.command: "{{ hostvars['k8s-control-plane-01']['join_worker_cmd'] }}"
      args:
        creates: /etc/kubernetes/kubelet.conf
```

### Playbook 12 — Instalação Resiliente do MetalLB (`12-instala-metallb.yml`)

```yaml
---
- name: 12 - Instala MetalLB LoadBalancer via Helm
  hosts: k8s-control-plane-01
  become: yes
  vars:
    kubeconfig_path: "/etc/kubernetes/admin.conf"
    metallb_namespace: "metallb-system"

  tasks:
    - name: Adicionar repositorio Helm do MetalLB
      kubernetes.core.helm_repository:
        name: metallb
        repo_url: "metallb-helm-repository-url"

    - name: Implantar Chart Helm do MetalLB
      kubernetes.core.helm:
        name: metallb
        chart_ref: metallb/metallb
        release_namespace: "{{ metallb_namespace }}"
        create_namespace: true
        state: present
        wait: yes
        kubeconfig: "{{ kubeconfig_path }}"

    - name: Aguardar pods do MetalLB ficarem Ready
      ansible.builtin.command: >
        kubectl wait --namespace {{ metallb_namespace }}
        --for=condition=ready pod
        --selector=app.kubernetes.io/component=controller
        --timeout=120s
        --kubeconfig={{ kubeconfig_path }}
      changed_when: false

    - name: Criar configuracao de IPAddressPool e L2Advertisement
      ansible.builtin.copy:
        dest: /tmp/metallb-config.yaml
        content: |
          apiVersion: metallb.io/v1beta1
          kind: IPAddressPool
          metadata:
            name: first-pool
            namespace: metallb-system
          spec:
            addresses:
              - 10.0.39.200-10.0.39.250
          ---
          apiVersion: metallb.io/v1beta1
          kind: L2Advertisement
          metadata:
            name: l2-adv
            namespace: metallb-system
          spec:
            ipAddressPools:
              - first-pool

    - name: Aplicar manifesto IPAddressPool com retentativas (Webhook Readiness)
      ansible.builtin.command: >
        kubectl apply -f /tmp/metallb-config.yaml
        --kubeconfig={{ kubeconfig_path }}
      register: metallb_config_output
      until: metallb_config_output.rc == 0
      retries: 10
      delay: 6
```

### Playbook 13 — Traefik Ingress Controller com Dashboard Isolado (`13-instala-traefik-ingress.yml`)

```yaml
---
- name: 13 - Instala Traefik Ingress Controller via Helm
  hosts: k8s-control-plane-01
  become: yes
  vars:
    traefik_namespace: "traefik"
    kubeconfig_path: "/etc/kubernetes/admin.conf"
    dashboard_domain: "traefik-k8s.nverse.local"

  tasks:
    - name: Adicionar repositorio Helm do Traefik
      kubernetes.core.helm_repository:
        name: traefik
        repo_url: "traefik-helm-repository-url"

    - name: Implantar Chart Helm do Traefik
      kubernetes.core.helm:
        name: traefik
        chart_ref: traefik/traefik
        release_namespace: "{{ traefik_namespace }}"
        create_namespace: true
        state: present
        wait: yes
        kubeconfig: "{{ kubeconfig_path }}"
        values:
          ingressRoute:
            dashboard:
              enabled: true

    - name: Criar manifesto do IngressRoute para o Dashboard do Traefik
      ansible.builtin.copy:
        dest: /tmp/traefik-dashboard-ingress.yaml
        content: |
          apiVersion: traefik.io/v1alpha1
          kind: IngressRoute
          metadata:
            name: traefik-dashboard
            namespace: {{ traefik_namespace }}
          spec:
            entryPoints:
              - web
            routes:
              - match: Host(`{{ dashboard_domain }}`)
                kind: Rule
                services:
                  - name: api@internal
                    kind: TraefikService

    - name: Aplicar IngressRoute do Dashboard no Kubernetes
      ansible.builtin.command: >
        kubectl apply -f /tmp/traefik-dashboard-ingress.yaml
        --kubeconfig={{ kubeconfig_path }}
      register: dashboard_ingress_output
      until: dashboard_ingress_output.rc == 0
      retries: 5
      delay: 4

    - name: Obter IP do servico Traefik via kubectl
      ansible.builtin.command: >
        kubectl get svc traefik -n {{ traefik_namespace }}
        --kubeconfig={{ kubeconfig_path }}
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
      register: traefik_ip
      changed_when: false

    - name: Exibir instrucoes de acesso ao Dashboard
      ansible.builtin.debug:
        msg:
          - "Traefik Ingress Controller ativo no IP da rede: {{ traefik_ip.stdout | default('Pendente') }}"
          - "Adicione no seu /etc/hosts local: {{ traefik_ip.stdout }} {{ dashboard_domain }}"
          - "Acesse o Dashboard em: http://{{ dashboard_domain }}/dashboard/"
```

### Playbook 16 — Aplicação de Teste HTTPS com TLS Cert-Manager (`16-deploy-aplicacao-teste-https.yml`)

```yaml
---
- name: 16 - Deploy Aplicacao Teste HTTPS (whoami)
  hosts: k8s-control-plane-01
  become: yes
  vars:
    kubeconfig_path: "/etc/kubernetes/admin.conf"
    domain_name: "whoami-k8s.nverse.local"

  tasks:
    - name: Criar manifesto da aplicacao de teste com Ingress TLS
      ansible.builtin.copy:
        dest: /tmp/whoami-ingress.yaml
        content: |
          ---
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: whoami-test
            namespace: default
          spec:
            replicas: 1
            selector:
              matchLabels:
                app: whoami-test
            template:
              metadata:
                labels:
                  app: whoami-test
              spec:
                containers:
                  - name: whoami
                    image: traefik/whoami:v1.10.1
                    ports:
                      - containerPort: 80
          ---
          apiVersion: v1
          kind: Service
          metadata:
            name: whoami-service
            namespace: default
          spec:
            ports:
              - port: 80
                targetPort: 80
            selector:
              app: whoami-test
          ---
          apiVersion: networking.k8s.io/v1
          kind: Ingress
          metadata:
            name: whoami-ingress
            namespace: default
            annotations:
              cert-manager.io/cluster-issuer: internal-ca-issuer
          spec:
            ingressClassName: traefik
            tls:
              - hosts:
                  - {{ domain_name }}
                secretName: whoami-nverse-tls
            rules:
              - host: {{ domain_name }}
                http:
                  paths:
                    - path: /
                      pathType: Prefix
                      backend:
                        service:
                          name: whoami-service
                          port:
                            number: 80

    - name: Aplicar manifesto no Kubernetes via kubectl
      ansible.builtin.command: >
        kubectl apply -f /tmp/whoami-ingress.yaml
        --kubeconfig={{ kubeconfig_path }}

    - name: Aguardar emissao do certificado TLS pelo Cert-Manager
      ansible.builtin.command: >
        kubectl get certificate whoami-nverse-tls
        --kubeconfig={{ kubeconfig_path }}
      register: cert_status
      until: "'True' in cert_status.stdout"
      retries: 10
      delay: 3
      changed_when: false

    - name: Exibir confirmacao de prontidao do Certificado
      ansible.builtin.debug:
        msg: "{{ cert_status.stdout }}"
```

---

## 5. Mapeamento de Task Templates no Ansible Semaphore

Para executar a automação de forma visual no **Ansible Semaphore**, utilize o mapeamento de tarefas abaixo:

| ID | Nome do Template | Playbook Filename | Inventário |
| :--- | :--- | :--- | :--- |
| **00** | `00 - Prepara Sistema Operacional` | `playbooks/00-base/00-prepara-so.yml` | `production.ini` |
| **01** | `01 - Configura Servidor NFS` | `playbooks/01-storage/01-configura-nfs-server.yml` | `production.ini` |
| **02** | `02 - Configura Keepalived (VIP)` | `playbooks/02-loadbalancer/02-configura-keepalived.yml` | `production.ini` |
| **03** | `03 - Configura HAProxy (LB 6443)` | `playbooks/02-loadbalancer/03-configura-haproxy.yml` | `production.ini` |
| **04** | `04 - Prepara Prereqs Kubernetes` | `playbooks/03-kubernetes/04-prepara-k8s-prereqs.yml` | `production.ini` |
| **05** | `05 - Init Control Plane 01` | `playbooks/03-kubernetes/05-init-control-plane-01.yml` | `production.ini` |
| **06** | `06 - Gera Tokens e Upload Certs` | `playbooks/03-kubernetes/06-gera-tokens-join.yml` | `production.ini` |
| **07** | `07 - Join Control Planes Secundarios` | `playbooks/03-kubernetes/07-join-control-planes.yml` | `production.ini` |
| **08** | `08 - Join Worker Nodes` | `playbooks/03-kubernetes/08-join-workers.yml` | `production.ini` |
| **09** | `09 - Instala CNI Calico` | `playbooks/03-kubernetes/09-instala-cni-calico.yml` | `production.ini` |
| **10** | `10 - Instala NFS Provisioner` | `playbooks/03-kubernetes/10-instala-nfs-provisioner.yml` | `production.ini` |
| **11** | `11 - Instala Metrics Server` | `playbooks/03-kubernetes/11-instala-metrics-server.yml` | `production.ini` |
| **12** | `12 - Instala MetalLB` | `playbooks/03-kubernetes/12-instala-metallb.yml` | `production.ini` |
| **13** | `13 - Instala Traefik Ingress` | `playbooks/03-kubernetes/13-instala-traefik-ingress.yml` | `production.ini` |
| **14** | `14 - Instala Cert-Manager` | `playbooks/03-kubernetes/14-instala-cert-manager.yml` | `production.ini` |
| **15** | `15 - Configura ClusterIssuer CA` | `playbooks/03-kubernetes/15-configura-cluster-issuer-ca.yml` | `production.ini` |
| **16** | `16 - Teste Aplicacao HTTPS` | `playbooks/03-kubernetes/16-deploy-aplicacao-teste-https.yml` | `production.ini` |
| **MASTER** | `00 - Esteira Completa` | `site.yml` | `production.ini` |

---

## 6. Guia de Validação e Troubleshooting

### 1. Testes de Diagnóstico no Cluster Kubernetes

Execute os comandos de verificação no nó `k8s-control-plane-01`:

```bash
# Verificar status dos nós do cluster
kubectl get nodes -o wide

# Verificar saúde de todos os pods de infraestrutura
kubectl get pods -A

# Validar o IP de LoadBalancer retornado pelo MetalLB
kubectl get svc -n traefik

# Validar certificados emitidos pelo Cert-Manager
kubectl get certificate -A
```

### 2. Principais Problemas Solucionados e Dicas de Troubleshooting

#### A. Erro de Webhook no MetalLB (`Internal error occurred: failed calling webhook`)
* **Causa:** O controller do MetalLB é implantado via Helm, mas a sua API de validação (`ValidatingWebhookConfiguration`) demora alguns segundos para inicializar os certificados internos antes de aceitar objetos `IPAddressPool`.
* **Solução:** Adicionada a task de espera `kubectl wait` combinada com o parâmetro `until` e `retries` no `kubectl apply` da playbook `12-instala-metallb.yml`.

#### B. Erro de Re-execução do `kubeadm join` (`/etc/kubernetes/kubelet.conf already exists`)
* **Causa:** Tentar rodar a esteira do Ansible em um cluster que já passou pelo procedimento de join causava erro de execução.
* **Solução:** Incluído o parâmetro `args: creates: /etc/kubernetes/kubelet.conf` nas playbooks 07 e 08, garantindo idempotência total.

#### C. Conflito de Nomes DNS entre Docker Swarm e Kubernetes
* **Causa:** Caso exista uma stack antiga do Traefik no Swarm respondendo pelo domínio `traeffik.nverse.local`, o navegador e a rede local tentarão acessar o ambiente antigo.
* **Solução:** Padronização do subdomínio do Kubernetes com o sufixo `-k8s.nverse.local`:
  * Dashboard do Traefik K8s: `http://traefik-k8s.nverse.local/dashboard/`
  * Aplicação de Teste HTTPS: `https://whoami-k8s.nverse.local`

#### D. Mapeamento de Hosts na Máquina Cliente
Adicione a seguinte entrada no arquivo `/etc/hosts` da máquina física (onde o navegador é executado):

```text
10.0.39.200 traefik-k8s.nverse.local whoami-k8s.nverse.local
```

---

## 7. Conclusão e Próximos Passos

Com esta esteira declarativa e totalmente orquestrada, seu ambiente Kubernetes de Alta Disponibilidade no Proxmox VE torna-se reprodutível em poucos minutos com apenas um clique no Ansible Semaphore via `site.yml`.

A infraestrutura conta com:
* **Alta Disponibilidade no Control Plane:** VRRP Keepalived + HAProxy no IP `10.0.39.50`.
* **Roteamento de Entrada e Ingress:** MetalLB (pool `10.0.39.200-250`) + Traefik Ingress.
* **Segurança Automática:** Cert-Manager gerando TLS via autoridade certificadora (CA) interna.
* **Armazenamento Persistente:** StorageClass dinâmica provisionada via NFS Server.

O ambiente está pronto para receber workloads de produção e a stack de observabilidade com Zabbix, Prometheus e Grafana!
