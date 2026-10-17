### 📁 Doc 8 — Servidor NFS e Provisionador Dinâmico StorageClass
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a configuração do Servidor NFS dedicado (`k8s-nfs-01`), exportação de volumes para a subrede e implantação do `nfs-subdir-external-provisioner` para suporte a `StorageClass: nfs-client` como padrão no cluster.  
**Pré-requisito:** VM `k8s-nfs-01` (IP `10.0.39.70`) com segundo disco de 100GB (`/dev/sdb`) provisionada.

---

#### 📋 Sumário
1. [Arquitetura de Armazenamento Compartilhado](#1-arquitetura-de-armazenamento-compartilhado)
2. [Configuração do Servidor NFS (k8s-nfs-01)](#2-configuração-do-servidor-nfs-k8s-nfs-01)
3. [Instalação dos Clientes NFS nos Worker Nodes](#3-instalação-dos-clientes-nfs-nos-worker-nodes)
4. [Implantação do NFS Subdir External Provisioner](#4-implantação-do-nfs-subdir-external-provisioner)
5. [Validação Prática com PVC Teste](#5-validação-prática-com-pvc-teste)

---

#### 1. Arquitetura de Armazenamento Compartilhado

```
[ Pod com PVC ] ──(Solicita Volume)──> [ StorageClass: nfs-client ]
                                               │
                                      (Provisiona Pasta)
                                               │
                                               ▼
                                 [ Servidor NFS: 10.0.39.70 ]
                                  Export: /srv/nfs/k8s (/dev/sdb)
```

---

#### 2. Configuração do Servidor NFS (`k8s-nfs-01`)

```bash
# 1. Formatar disco secundário de 100GB
sudo mkfs.ext4 /dev/sdb

# 2. Criar diretório de montagem
sudo mkdir -p /srv/nfs/k8s

# 3. Adicionar montagem no /etc/fstab
echo "/dev/sdb /srv/nfs/k8s ext4 defaults,noatime,nodiratime 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# 4. Instalar o servidor NFS
sudo apt update && sudo apt install -y nfs-kernel-server

# 5. Configurar exportação no /etc/exports
echo "/srv/nfs/k8s 10.0.39.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

---

#### 3. Instalação dos Clientes NFS nos Worker Nodes

Executado em **todos os Control Planes e Workers**:

```bash
sudo apt update && sudo apt install -y nfs-common
```

---

#### 4. Implantação do NFS Subdir External Provisioner

Comando do Helm executado via Ansible (`09-instala-nfs-provisioner.yml`):

```bash
helm install nfs-client nfs-subdir-external-provisioner \
  --set nfs.server=10.0.39.70 \
  --set nfs.path=/srv/nfs/k8s \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true
```

---

#### 5. Validação Prática com PVC Teste

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f test-pvc.yaml
kubectl get pvc,pv
```

##### Saída Esperada:
```
NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/test-nfs-pvc   Bound    pvc-8f2c3d4a-5b6c-7d8e-9f0a-1b2c3d4e5f6a   1Gi        RWX            nfs-client     10s
```

---

- **Próximo Passo**: **[09-Ecossistema-Helm-DevOps.md](./09-Ecossistema-Helm-DevOps.md)**.
