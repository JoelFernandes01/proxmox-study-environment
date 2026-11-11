# Manual Operacional Definitivo: Recriacao de Infraestrutura, Implantacao do Kubernetes HA e Stack Zabbix 8.0 LTS

Este manual estabelece o procedimento operacional padrao para a recriacao do ambiente virtualizado no Proxmox VE, estabelecimento de credenciais SSH, provisionamento estrito do cluster Kubernetes High Availability via Ansible Semaphore e implantacao da solucao de observabilidade Zabbix 8.0 LTS.

---

## 1. Arquitetura e Mapeamento de Recursos do Ambiente

A infraestrutura e composta por 6 maquinas virtuais principais rodando Ubuntu Server, 1 servidor NFS dedicado e balanceadores de carga com IP Virtual flutuante.

| Hostname | IP Fixo | Funcao no Cluster | Recursos Alocados |
| :--- | :--- | :--- | :--- |
| `k8s-control-plane-01` | `10.0.39.43` | Master Principal | 2 vCPU, 4 GB RAM, 30 GB Disk |
| `k8s-control-plane-02` | `10.0.39.44` | Master Secundario | 2 vCPU, 4 GB RAM, 30 GB Disk |
| `k8s-control-plane-03` | `10.0.39.45` | Master Secundario | 2 vCPU, 4 GB RAM, 30 GB Disk |
| `k8s-worker-01` | `10.0.39.46` | Worker Node | 2 vCPU, 4 GB RAM, 40 GB Disk |
| `k8s-worker-02` | `10.0.39.47` | Worker Node | 2 vCPU, 4 GB RAM, 40 GB Disk |
| `k8s-worker-03` | `10.0.39.48` | Worker Node | 2 vCPU, 4 GB RAM, 40 GB Disk |


---

## 2. Fase 1: Recriacao Completa das VMs no Proxmox VE

Quando for necessario reiniciar o ambiente a partir do zero, execute os procedimentos no Shell do hypervisor Proxmox VE para recriar as maquinas virtuais limpas a partir do Template Cloud-Init (VM ID 9000).

1. **Parada e Remocao das VMs anteriores (IDs 101 a 106)**:
   Parar as VMs em execução (`qm stop <vmid>`) e remover a configuracao anterior.
2. **Clonagem a partir do Template Base Cloud-Init (ID 9000)**:
   Clonar o template base (`qm clone 9000 <vmid> --name <hostname> --full 1`), configurar o IP estatico (`qm set <vmid> --ipconfig0 ip=<ip>/24,gw=10.0.39.1`), associar as chaves SSH publicas e iniciar a maquina virtual (`qm start <vmid>`).

---

## 3. Fase 2: Configuracao de Chaves SSH e Teste de Conectividade Ansible

Apos o boot das VMs (aproximadamente 60 segundos), configure o acesso SSH sem senha na sua maquina de deploy ou no servidor Semaphore.

### 3.1. Geracao da Chave SSH Local
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 3.2. Copiar a Chave Publica para Todos os Nos do Cluster
```bash
IPS=("10.0.39.43" "10.0.39.44" "10.0.39.45" "10.0.39.46" "10.0.39.47" "10.0.39.48")

for ip in "${IPS[@]}"; do
  echo "Copiando chave SSH para $ip..."
  ssh-copy-id -o StrictHostKeyChecking=no connect@$ip
done
```

### 3.3. Teste de Conectividade Automatizado via Ansible
No diretorio do repositorio Git, execute a validacao de inventario:
```bash
ansible all -i production.ini -m ping
```
* **Resultado Esperado**: Todas as 6 maquinas virtuais devem responder com status `SUCCESS` em verde.


---

## 4. Fase 3: Esteira Kubernetes HA — Execucao Playbook por Playbook & Protocolo de Validacao

Execute cada Task Template no Semaphore individualmente e execute o teste de validacao indicado antes de prosseguir para o proximo passo.

### 4.1. Playbook `04-prepara-k8s-prereqs.yml`
* **Acao**: Desativa a memoria swap permanentemente, carrega os modulos de kernel (`overlay`, `br_netfilter`), configura parametros sysctl de rede e instala o runtime `containerd`.
* **Comando de Teste no Terminal**:
  ```bash
  ansible all -i production.ini -a "swapon -s" --become
  ansible all -i production.ini -a "systemctl is-active containerd" --become
  ```
* **Resultado Esperado**:
  * O comando `swapon -s` deve retornar uma saida vazia em todos os nos.
  * O servico `containerd` deve retornar o status `active` em 100% dos nos.

### 4.2. Playbook `05-init-control-plane-01.yml`
* **Acao**: Realiza a limpeza preventiva do `kubeadm` e `etcd`, inicializa a CA e o Control Plane no no `10.0.39.43` e gera o arquivo seguro `/etc/kubernetes/admin-local.conf` com o IP local.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ssh connect@10.0.39.43 "cat /etc/kubernetes/admin-local.conf | grep server"
  ```
* **Resultado Esperado**:
  * O no `k8s-control-plane-01` deve ser listado em status `NotReady` (aguardando CNI).
  * O endpoint configurado deve ser exatamente `server: https://10.0.39.43:6443`.

### 4.3. Playbook `06-gera-tokens-join.yml`
* **Acao**: Executa o upload das chaves de certificados (`kubeadm init phase upload-certs`) e gera o token de associacao em memoria para os demais nos.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "sudo kubeadm token list"
  ```
* **Resultado Esperado**: Exibicao de pelo menos um token ativo com tempo de expiracao de 24 horas.

### 4.4. Playbook `07-join-control-planes.yml`
* **Acao**: Executa o expurgo de dados legados e integra os Control Planes secundarios (`k8s-control-plane-02` e `k8s-control-plane-03`) ao plano de controle HA.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n kube-system -l component=etcd"
  ```
* **Resultado Esperado**:
  * Os 3 nos de Control Plane (`01`, `02` e `03`) devem constar na lista de nos.
  * Devem existir 3 pods do `etcd` operacionais em `1/1 Running`.

### 4.5. Playbook `08-join-workers.yml`
* **Acao**: Limpa a pilha de rede e associa os Worker Nodes (`k8s-worker-01`, `02` e `03`) ao cluster.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ```
* **Resultado Esperado**: Todos os 6 nos do cluster (`3 Control Planes` + `3 Workers`) visiveis no cluster.

### 4.6. Playbook `09-instala-cni-calico.yml`
* **Acao**: Implanta o plugin de rede Calico CNI utilizando a conexao direta `admin-local.conf` para evitar falhas TLS.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n kube-system -l k8s-app=calico-node"
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes"
  ```
* **Resultado Esperado**:
  * 6 pods do `calico-node` em estado `1/1 Running`.
  * **Todos os 6 nos do cluster mudam para o status `Ready`**.

### 4.7. Playbook `10-instala-nfs-provisioner.yml`
* **Acao**: Configura o `nfs-subdir-external-provisioner` via Helm conectado ao servidor NFS (`10.0.39.46`) e estabelece a StorageClass padrao `nfs-client`.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get sc"
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n kube-system -l app=nfs-client-provisioner"
  ```
* **Resultado Esperado**:
  * A StorageClass `nfs-client` listada com `(default)`.
  * Pod do NFS provisioner em `1/1 Running`.

### 4.8. Playbook `11-instala-metrics-server.yml`
* **Acao**: Deploy do Metrics Server com o patch `--kubelet-insecure-tls` para permitir a coleta de metricas de CPU e Memoria dos nos e pods.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf top nodes"
  ```
* **Resultado Esperado**: Exibicao da porcentagem e uso absoluto de CPU e Memoria em todos os 6 nos.

### 4.9. Playbook `12-instala-metallb.yml`
* **Acao**: Implanta o MetalLB LoadBalancer (versao `0.13.12` sem FRR) e aplica os recursos `IPAddressPool` (`10.0.39.200-250`) e `L2Advertisement`.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n metallb-system"
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get ipaddresspool -n metallb-system"
  ```
* **Resultado Esperado**: Pods do controller e speakers do MetalLB em `Running` e pool `first-pool` cadastrado.

### 4.10. Playbook `13-instala-traefik-ingress.yml`
* **Acao**: Implanta o Traefik Ingress Controller via Helm e expoe a porta HTTP atraves de um IP do MetalLB.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get svc -n traefik"
  ```
* **Resultado Esperado**: Servico `traefik` do tipo `LoadBalancer` com um IP atribuido no range `10.0.39.20x`.

### 4.11. Playbooks `14-instala-cert-manager.yml` e `15-configura-cluster-issuer-ca.yml`
* **Acao**: Instala o Jetstack Cert-Manager com CRDs e configura o `ClusterIssuer` para emissao automatica de certificados TLS/SSL.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get clusterissuers"
  ```
* **Resultado Esperado**: ClusterIssuer `ca-issuer` em estado `Ready`.

## 5. Fase 4: Implantacao e Validacao da Stack Zabbix 8.0 LTS

Apos a consolidacao do cluster Kubernetes, execute o deploy da solucao de monitoramento Zabbix 8.0 LTS.

### 5.1. Playbook `00-prepara-namespaces-storage-zabbix.yml`
* **Acao**: Cria o namespace isolado `zabbix` e aloca o volume persistente NFS `zabbix-db-pvc` de 10GB.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pvc -n zabbix"
  ```
* **Resultado Esperado**: PVC `zabbix-db-pvc` com status `Bound`.

### 5.2. Playbook `01-configura-banco-zabbix.yml`
* **Acao**: Implanta o banco de dados PostgreSQL 16 Alpine com secrets de autenticacao e service ClusterIP.
* **Comando de Teste via SSH**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n zabbix -l app=zabbix-postgresql"
  ```
* **Resultado Esperado**: Pod do PostgreSQL em `1/1 Running`.

### 5.3. Playbook `02-deploy-zabbix-server.yml`
* **Acao**: Sobe o Zabbix Server 8.0 LTS, a interface Zabbix Web Nginx 8.0 LTS e vincula a UI ao IP fixo de LoadBalancer `10.0.39.201`.
* **Comando de Teste via SSH e Curl**:
  ```bash
  ssh connect@10.0.39.43 "kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n zabbix"
  ```
* **Resultado Esperado**: Pods `zabbix-server` e `zabbix-web` em `1/1 Running`.

### 5.4. Playbook `03-instala-zabbix-agents-vms.yml`
* **Acao**: Instala o Zabbix Agent 2 (v8.0 LTS) em todas as VMs e aponta a comunicacao para o servidor `10.0.39.201`.
* **Comando de Teste no Terminal Ansible**:
  ```bash
  ansible all -i production.ini -a "systemctl is-active zabbix-agent2" --become
  ```
* **Resultado Esperado**: Todos os agentes respondendo com o status `active`.

### 5.5. Playbooks `07-configura-datasources.yml` e `08-importa-dashboards.yml`
* **Acao**: Registra os DataSources do Prometheus e da API do Zabbix 8.0 no Grafana e carrega os dashboards automatizados de infraestrutura.
* **Resultado Esperado**: Dashboards exibindo graficos de consumo de CPU, Memoria e conectividade dos nos em tempo real.

---

## 6. Tabela Matriz de Checagem Rapida do Ambiente

| Componente | Comando de Validacao Rapida | Status de Sucesso |
| :--- | :--- | :--- |
| **VMs Proxmox** | `ansible all -i production.ini -m ping` | All nodes `SUCCESS` |
| **K8s Nodes** | `kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get nodes` | 6 nodes `Ready` |
| **Rede CNI** | `kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n kube-system -l k8s-app=calico-node` | 6 pods `1/1 Running` |
| **Storage NFS** | `kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get sc` | `nfs-client (default)` |
| **Metrics Server**| `kubectl --kubeconfig=/etc/kubernetes/admin-local.conf top nodes` | Exibe consumo CPU/RAM |
| **MetalLB** | `kubectl --kubeconfig=/etc/kubernetes/admin-local.conf get pods -n metallb-system` | Controller/Speakers `Running` |
| **Zabbix 8.0 UI** | `kubectl get svc -n zabbix` | External IP `10.0.39.201` |
| **Zabbix Agents**| `ansible all -i production.ini -a "systemctl is-active zabbix-agent2" --become` | All agents `active` |
