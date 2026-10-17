### 🖼 Doc 1 — Template Proxmox com Cloud-Init
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar o processo completo de criação de templates Proxmox com Cloud-Init funcional para nós de Kubernetes, incluindo customizações de SO, scripts, resolução do bug do cloud-init desabilitado e testes de validação.  
**Pré-requisito:** Proxmox VE 9.x, acesso root/sudo, ferramentas `libguestfs-tools` (`virt-customize`), imagem Cloud oficial do Ubuntu 24.04/26.04.

---

#### 📋 Sumário
1. [Por Que Templates Importam](#1-por-que-templates-importam)
2. [O Problema Que Resolvemos](#2-o-problema-que-resolvemos)
3. [Convenção de IDs](#3-convenção-de-ids)
4. [Fluxo Completo de Criação](#4-fluxo-completo-de-criação)
5. [Etapa 1 — Script de Preparação da Imagem (01-prepare-image.sh)](#5-etapa-1--script-de-preparação-da-imagem)
6. [Etapa 2 — Criação e Configuração da VM no Proxmox CLI](#6-etapa-2--criação-e-configuração-da-vm-no-proxmox-cli)
7. [Etapa 3 — Validação com Clone de Teste](#7-etapa-3--validação-com-clone-de-teste)
8. [Armadilhas Comuns & Troubleshooting](#8-armadilhas-comuns--troubleshooting)
9. [Boas Práticas & Referências Cruzadas](#9-boas-práticas--referências-cruzadas)

---

#### 1. Por Que Templates Importam
Um template Proxmox é a **fonte da verdade** para o provisionamento automatizado via Terraform. Cada nó clonado herda o estado base do sistema operacional e utiliza o Cloud-Init para injetar personalizações exclusivas no primeiro boot (hostname, IP fixo, chave SSH).

```
Template Clean (Estado Base) + Cloud-Init (Injeção de Config) = VM Kubernetes Pronta e Única
```

---

#### 2. O Problema Que Resolvemos
Imagens Cloud-Init padrão frequentemente causam falhas quando clonadas em lote, tais como:
| Sintoma | Causa Raiz | Correção Aplicada no Template |
|---|---|---|
| ❌ Hostname genérico e repetido | `/etc/hostname` mantido na imagem original | `truncate -s 0 /etc/hostname` |
| ❌ Cloud-Init ignora o Terraform | `/etc/cloud/cloud-init.disabled` presente | `rm -f /etc/cloud/cloud-init.disabled` |
| ❌ Estado "gasto" do Cloud-Init | Dados de inicialização prévia gravados | `cloud-init clean --logs --seed` |
| ❌ Conflito de Machine ID | ID do systemd compartilhado por todas as VMs | `truncate -s 0 /etc/machine-id` |
| ❌ Impressões digitais SSH idênticas | Chaves de host geradas previamente | `rm -f /etc/ssh/ssh_host_*` |

---

#### 3. Convenção de IDs
| Faixa | Uso |
|---|---|
| **8000** | Template Ubuntu Server 26.04 / 24.04 LTS (Base Kubernetes) |
| **9400 - 9408** | Nós do Cluster Kubernetes e Serviços de Apoio |

---

#### 4. Fluxo Completo de Criação
```
1. Download da Imagem Cloud Oficial (Ubuntu)
   ↓
2. Customização Offline via virt-customize (Pacotes + Limpeza)
   ↓
3. Criação da VM no Proxmox (`qm create 8000`)
   ↓
4. Importação e Anexo do Disco (`qm importdisk`)
   ↓
5. Configuração de Hardware (SCSI single, iothread, ssd, growroot)
   ↓
6. Anexo do Drive Cloud-Init (`qm set --ide2 local:cloudinit`)
   ↓
7. Conversão para Template (`qm template 8000`)
```

---

#### 5. Etapa 1 — Script de Preparação da Imagem

##### `01-prepare-image.sh`
```bash
#!/bin/bash
set -euo pipefail

IMAGE_URL="${1:?Uso: $0 <url-da-imagem> <arquivo-saida.qcow2>}"
OUTPUT="${2:?Uso: $0 <url-da-imagem> <arquivo-saida.qcow2>}"

echo "📥 Baixando imagem cloud..."
wget -O "$OUTPUT" "$IMAGE_URL"

echo "🛠 Customizando imagem via virt-customize..."
virt-customize -a "$OUTPUT" \
  --install qemu-guest-agent,cloud-initramfs-growroot,curl,wget,htop \
  --update \
  --run-command "truncate -s 0 /etc/machine-id" \
  --run-command "rm -f /var/lib/dbus/machine-id" \
  --run-command "ln -s /etc/machine-id /var/lib/dbus/machine-id" \
  --run-command "truncate -s 0 /etc/hostname" \
  --run-command "rm -f /etc/cloud/cloud-init.disabled" \
  --run-command "rm -rf /var/lib/cloud/*" \
  --run-command "rm -f /etc/netplan/*.yaml" \
  --run-command "rm -f /etc/ssh/ssh_host_*" \
  --run-command "cloud-init clean --logs --seed" \
  --run-command "apt clean"

echo "✅ Imagem $OUTPUT pronta para importação no Proxmox."
```

##### Execução
```bash
./01-prepare-image.sh \
  "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" \
  ubuntu-k8s-template.qcow2
```

---

#### 6. Etapa 2 — Criação e Configuração da VM no Proxmox CLI

```bash
# 1. Criar a VM base para o template
qm create 8000 \
  --name ubuntu-k8s-template \
  --memory 2048 \
  --cores 2 --sockets 1 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket --vga serial0

# 2. Importar o disco customizado no datastore
qm importdisk 8000 ubuntu-k8s-template.qcow2 storage-vms

# 3. Anexar o disco com suporte a iothread, SSD e discard (TRIM)
qm set 8000 \
  --scsihw virtio-scsi-single \
  --scsi0 storage-vms:8000/vm-8000-disk-0.raw,discard=on,iothread=1,ssd=1

# 4. Ajustar ordem de boot e expanção do disco
qm set 8000 --boot order=scsi0
qm resize 8000 scsi0 50G

# 5. Anexar a drive de injeção de metadados Cloud-Init
qm set 8000 --ide2 storage-vms:cloudinit

# 6. Converter para Template
qm template 8000
```

---

#### 7. Etapa 3 — Validação com Clone de Teste

```bash
# Clonar para teste
qm clone 8000 8999 --name k8s-teste-template --full true

# Configurar IP e Chave SSH
qm set 8999 \
  --ciuser connect \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=10.0.39.199/24,gw=10.0.39.1

qm start 8999
sleep 30

# Validação SSH
ssh connect@10.0.39.199 "hostname -f && cloud-init status --wait"
# Esperado: status: done

# Limpeza
qm stop 8999 && qm destroy 8999
```

---

#### 8. Armadilhas Comuns & Troubleshooting
1. **`cloud-init.disabled`**: Se presente, o Cloud-Init nunca roda e a VM não recebe as configurações do Terraform. O `virt-customize` resolve garantindo sua exclusão.
2. **Falta do `qemu-guest-agent`**: Sem ele, o Proxmox não descobre o IP real da VM e os scripts de espera do Terraform expiram.

---

#### 9. Boas Práticas & Referências Cruzadas
- **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)**: Utiliza este template ID 8000 para provisionar os 9 nós do cluster.
- **[03-Base-Ubuntu-Kubernetes.md](./03-Base-Ubuntu-Kubernetes.md)**: Aplica as configurações do kernel Kubernetes nos nós clonados.
