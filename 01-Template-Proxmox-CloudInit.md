# 🖼️ Doc 1 — Template Proxmox com Cloud-Init

> **Autor:** Joel Fernandes  
> **Data:** 02/10/2026  
> **Objetivo:** Documentar o processo completo de criação de templates Proxmox com cloud-init funcional, incluindo scripts, boas práticas, armadilhas e validação.  
> **Pré-requisito:** Proxmox 9.x, `virt-customize` (libguestfs-tools), acesso root/sudo, imagens cloud oficiais do Ubuntu.

---

## 📋 Sumário

1. [Por Que Templates Importam](#1-por-que-templates-importam)
2. [O Problema Que Resolvemos](#2-o-problema-que-resolvemos)
3. [Convenção de IDs](#3-convenção-de-ids)
4. [Fluxo Completo](#4-fluxo-completo)
5. [Etapa 1 — Baixar e Customizar a Imagem](#5-etapa-1--baixar-e-customizar-a-imagem)
6. [Etapa 2 — Criar VM no Proxmox](#6-etapa-2--criar-vm-no-proxmox)
7. [Etapa 3 — Anexar Disco e Configurar](#7-etapa-3--anexar-disco-e-configurar)
8. [Etapa 4 — Resize e Cloud-Init](#8-etapa-4--resize-e-cloud-init)
9. [Etapa 5 — Converter em Template](#9-etapa-5--converter-em-template)
10. [Etapa 6 — Validar com Clone](#10-etapa-6--validar-com-clone)
11. [Armadilhas Comuns](#11-armadilhas-comuns)
12. [Boas Práticas](#12-boas-práticas)
13. [Referências Cruzadas](#13-referências-cruzadas)
14. [Troubleshooting — Timeout e Resíduos no Storage](#14-troubleshooting--timeout-e-resíduos-no-storage)

---

## 1. Por Que Templates Importam

Um template Proxmox é a **fonte da verdade** para clonagem. Cada VM criada a partir dele herda o **estado base** — e o cloud-init injeta a **personalização** por clone (IP, hostname, chave SSH).

**Fluxo ideal:**

```
Template (estado base) + Cloud-Init (personalização) = VM pronta e única
```

Se o template estiver **errado**, todos os clones herdam o erro. Foi exatamente o que vivemos.

---

## 2. O Problema Que Resolvemos

As VMs clonadas estavam subindo com:

| Sintoma | Causa |
|---------|-------|
| ❌ Hostname `ubuntu-26-server` em todas | `/etc/hostname` herdado do template |
| ❌ IP via DHCP (não o fixo do Terraform) | `/etc/netplan/` herdado com DHCP |
| ❌ Cloud-init ignorando o Terraform | `/etc/cloud/cloud-init.disabled` presente + estado "gasto" |
| ❌ Mesma identidade systemd | `/etc/machine-id` não zerado |
| ❌ Mesmas chaves SSH de host | `/etc/ssh/ssh_host_*` não removidas |

**Diagnóstico confirmado:**

```bash
# Na VM clonada
systemctl status cloud-init
# → Unit cloud-init.service could not be found.

ls /etc/cloud/
# → cloud-init.disabled presente

ls -la /var/lib/cloud/
# → instance -> iid-datasource-none (estado gasto)
```

**Tradução**: o cloud-init estava **desabilitado** e com **estado gasto**. O Terraform aplicava `initialization { ... }` em vão — a VM ignorava tudo.

---

## 3. Convenção de IDs

Adotamos uma convenção numérica para organização:

| Faixa | Uso |
|-------|-----|
| `100-199` | VMs de produção |
| `200-299` | VMs de teste |
| `1000-1999` | Containers LXC |
| **`8000-8099`** | **Templates Ubuntu 26** |
| **`8100-8199`** | **Templates Ubuntu 24** |
| `8200-8299` | Templates Ubuntu 22 |
| `9000-9099` | VMs Docker Swarm (managers) |
| `9100-9199` | VMs Docker Swarm (workers) |

**Templates atuais:**

| VM ID | Nome | Versão |
|-------|------|--------|
| `8000` | `ubuntu-server-26-template` | Ubuntu 26.04 LTS |
| `8100` | `ubuntu-server-24-template` | Ubuntu 24.04 LTS |

---

## 4. Fluxo Completo

```
1. Baixar imagem cloud oficial
   ↓
2. Customizar com virt-customize (offline)
   ↓
3. Criar VM no Proxmox
   ↓
4. Importar disco
   ↓
5. Anexar disco (scsi0, iothread, ssd, discard)
   ↓
6. Configurar boot + resize
   ↓
7. Montar drive cloud-init (ide2)
   ↓
8. Converter em template
   ↓
9. Validar com clone de teste
```

---

## 5. Etapa 1 — Baixar e Customizar a Imagem

### 5.1 URLs por versão do Ubuntu

| Versão | Codename | URL |
|--------|----------|-----|
| Ubuntu 26.04 | `resolute` | `https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img` |
| Ubuntu 24.04 | `noble` | `https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img` |
| Ubuntu 22.04 | `jammy` | `https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img` |

### 5.2 Script `01-prepare-image.sh`

```bash
#!/bin/bash
set -euo pipefail

# Uso: ./01-prepare-image.sh <url-da-imagem> <nome-do-qcow2>
IMAGE_URL="${1:?Uso: $0 <url> <arquivo.qcow2>}"
OUTPUT="${2:?Uso: $0 <url> <arquivo.qcow2>}"

wget -O "$OUTPUT" "$IMAGE_URL"

virt-customize -a "$OUTPUT" \
  --install qemu-guest-agent,cloud-initramfs-growroot \
  --update \
  --run-command "truncate -s 0 /etc/machine-id" \
  --run-command "rm -f /var/lib/dbus/machine-id" \
  --run-command "ln -s /etc/machine-id /var/lib/dbus/machine-id" \
  --run-command "truncate -s 0 /etc/hostname" \
  --run-command "rm -f /etc/cloud/cloud-init.disabled" \
  --run-command "rm -rf /var/lib/cloud/*" \
  --run-command "rm -f /etc/netplan/*.yaml" \
  --run-command "rm -f /etc/ssh/ssh_host_*" \
  --run-command "rm -f /root/.bash_history /home/*/.bash_history" \
  --run-command "rm -rf /var/log/* /tmp/* /var/tmp/*" \
  --run-command "cloud-init clean --logs --seed" \
  --run-command "apt clean" \
  --run-command "history -c || true"

echo "✅ Imagem $OUTPUT pronta."
```

### 5.3 Uso

```bash
# Ubuntu 26
./01-prepare-image.sh \
  "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img" \
  ubuntu-26.qcow2

# Ubuntu 24
./01-prepare-image.sh \
  "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" \
  ubuntu-24.qcow2
```

### 5.4 O Que Cada Comando Faz

| Comando | Motivo |
|---------|--------|
| `--install qemu-guest-agent` | Integração com Proxmox (IP visível, shutdown graceful) |
| `--install cloud-initramfs-growroot` | Expande o filesystem automaticamente no primeiro boot |
| `--update` | Mantém o template atualizado |
| `truncate -s 0 /etc/machine-id` | Zera identidade systemd |
| `rm -f /var/lib/dbus/machine-id` + symlink | Recria o symlink correto |
| `truncate -s 0 /etc/hostname` | Zera hostname herdado |
| `rm -f /etc/cloud/cloud-init.disabled` | **DESTRAVA o cloud-init** (bug principal) |
| `rm -rf /var/lib/cloud/*` | Limpa estado "gasto" do cloud-init |
| `rm -f /etc/netplan/*.yaml` | cloud-init cria por clone |
| `rm -f /etc/ssh/ssh_host_*` | Cada clone gera as suas chaves |
| `rm -f ...bash_history` | Limpa histórico |
| `rm -rf /var/log/* /tmp/* /var/tmp/*` | Limpa logs e temporários |
| `cloud-init clean --logs --seed` | Limpa TUDO do cloud-init |
| `apt clean` | Reduz tamanho |

---

## 6. Etapa 2 — Criar VM no Proxmox

```bash
qm create <VM_ID> \
  --name <NOME> \
  --memory 2048 \
  --sockets 2 --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --numa 1 \
  --ostype l26 \
  --balloon 4096 \
  --ciupgrade 1 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0
```

### Exemplos

```bash
# Ubuntu 26 (VM ID 8000)
qm create 8000 \
  --name ubuntu-server-26-template \
  --memory 2048 \
  --sockets 2 --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --numa 1 \
  --ostype l26 \
  --balloon 4096 \
  --ciupgrade 1 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0

# Ubuntu 24 (VM ID 8100)
qm create 8100 \
  --name ubuntu-server-24-template \
  --memory 2048 \
  --sockets 2 --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --numa 1 \
  --ostype l26 \
  --balloon 4096 \
  --ciupgrade 1 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0
```

### Importar o disco

```bash
qm importdisk <VM_ID> <ARQUIVO>.qcow2 local --format qcow2
```

**Exemplo:**

```bash
qm importdisk 8000 ubuntu-26.qcow2 local --format qcow2
qm importdisk 8100 ubuntu-24.qcow2 local --format qcow2
```

> 💡 **O disco é importado como `unused0`** — não está anexado à VM ainda. Isso é esperado.

---

## 7. Etapa 3 — Anexar Disco e Configurar

### 7.1 Anexar disco com otimizações

```bash
qm set <VM_ID> \
  --scsihw virtio-scsi-single \
  --scsi0 local:<VM_ID>/vm-<VM_ID>-disk-0.qcow2,ssd=1,iothread=1,discard=on
```

**O que cada opção faz:**

| Opção | Significado |
|-------|-------------|
| `virtio-scsi-single` | Controladora SCSI com suporte a `iothread` (1 thread por disco) |
| `ssd=1` | Marca o disco como SSD (otimiza I/O no guest) |
| `iothread=1` | Thread dedicada de I/O (resolve contenção em hosts com múltiplas VMs) |
| `discard=on` | TRIM habilitado |

### 7.2 Configurar ordem de boot

```bash
qm set <VM_ID> --boot order=scsi0
```

---

## 8. Etapa 4 — Resize e Cloud-Init

### 8.1 Resize do disco

```bash
qm resize <VM_ID> scsi0 50G
```

> ⚠️ **`qm resize` só aumenta o disco virtual**, não o filesystem. O `cloud-initramfs-growroot` (instalado no `virt-customize`) expande o filesystem no primeiro boot do clone.

### 8.2 Montar drive cloud-init

```bash
qm set <VM_ID> --ide2 local:cloudinit
```

> 💡 Isso cria um "disco" virtual (ISO) que o Proxmox usa para injetar config (IP, hostname, chave SSH) nos clones.

---

## 9. Etapa 5 — Converter em Template

### 9.1 Converter

```bash
qm template <VM_ID>
```

> ⚠️ **Irreversível** (a não ser clonando para VM normal e reconvertendo).

### 9.2 Validar

```bash
qm config <VM_ID> | grep -E "template|name|scsi0|ide2|scsihw|boot"
```

**Esperado:**

```
name: ubuntu-server-26-template
scsi0: local:8000/base-8000-disk-0.qcow2,discard=on,iothread=1,size=50G,ssd=1
scsihw: virtio-scsi-single
ide2: local:8000/vm-8000-cloudinit.qcow2,media=cdrom
boot: order=scsi0
template: 1
```

> 💡 **O disco muda de `vm-` para `base-`**: quando converte em template, o Proxmox renomeia o disco para `base-<VM_ID>-disk-0.qcow2` (porque ele vira a **base** para linked clones).

---

## 10. Etapa 6 — Validar com Clone

### 10.1 Clonar

```bash
qm clone <TEMPLATE_ID> <TESTE_ID> --name teste-template --full true
```

### 10.2 Configurar cloud-init

```bash
qm set <TESTE_ID> \
  --ciuser connect \
  --sshkey ~/.ssh/authorized_keys \
  --ipconfig0 ip=10.0.39.150/24,gw=10.0.39.1
```

### 10.3 Iniciar

```bash
qm start <TESTE_ID>
sleep 40
```

### 10.4 Validar (5 itens)

```bash
# 1. Hostname
ssh connect@10.0.39.150 "hostname -f"
# Esperado: teste-template

# 2. IP fixo
ssh connect@10.0.39.150 "ip -4 addr show | grep inet | grep -v 127.0.0.1"
# Esperado: inet 10.0.39.150/24 ... eth0

# 3. Cloud-init rodou
ssh connect@10.0.39.150 "cloud-init status --wait"
# Esperado: status: done

# 4. Netplan correto (sem DHCP)
ssh connect@10.0.39.150 "sudo cat /etc/netplan/*.yaml"
# Esperado: addresses: - "10.0.39.150/24"

# 5. Bug removido
ssh connect@10.0.39.150 "ls /etc/cloud/cloud-init.disabled"
# Esperado: No such file or directory
```

### 10.5 Limpar o teste

```bash
qm stop <TESTE_ID>
qm destroy <TESTE_ID>
```

---

## 11. Armadilhas Comuns

### 11.1 `cloud-init.disabled` presente

**Sintoma**: cloud-init ignorado em todos os clones.  
**Causa**: arquivo `/etc/cloud/cloud-init.disabled` existe no template.  
**Solução**: `rm -f /etc/cloud/cloud-init.disabled` no `virt-customize`.

### 11.2 Estado "gasto" do cloud-init

**Sintoma**: cloud-init "acha" que já rodou e pula.  
**Causa**: `/var/lib/cloud/instance` aponta para `iid-datasource-none`.  
**Solução**: `rm -rf /var/lib/cloud/*` + `cloud-init clean --logs --seed`.

### 11.3 Hostname herdado

**Sintoma**: todos os clones têm o mesmo hostname (`ubuntu-26-server`).  
**Causa**: `/etc/hostname` do template não foi zerado.  
**Solução**: `truncate -s 0 /etc/hostname`.

### 11.4 Netplan com DHCP

**Sintoma**: clone sobe com IP aleatório, ignorando o `--ipconfig0`.  
**Causa**: `/etc/netplan/*.yaml` do template tem `dhcp4: true`.  
**Solução**: `rm -f /etc/netplan/*.yaml` (cloud-init cria por clone).

### 11.5 SSH host keys duplicadas

**Sintoma**: todas as VMs têm a mesma fingerprint SSH (alerta de segurança).  
**Causa**: `/etc/ssh/ssh_host_*` herdadas do template.  
**Solução**: `rm -f /etc/ssh/ssh_host_*` (cada clone gera as suas).

### 11.6 machine-id duplicado

**Sintoma**: systemd/journald com conflito, IP de logs repetido.  
**Causa**: `/etc/machine-id` herdado do template.  
**Solução**: `truncate -s 0 /etc/machine-id` + symlink correto.

### 11.7 Disco não expande

**Sintoma**: `qm resize` feito, mas `df -h` mostra 3.5 GB.  
**Causa**: `cloud-initramfs-growroot` não instalado.  
**Solução**: `--install cloud-initramfs-growroot` no `virt-customize`.

### 11.8 `iothread` sem efeito

**Sintoma**: host trava ao subir várias VMs simultaneamente.  
**Causa**: `scsi_hardware` não é `virtio-scsi-single`.  
**Solução**: `qm set <VM_ID> --scsihw virtio-scsi-single --scsi0 ...,iothread=1`.

### 11.9 Template é imutável

**Sintoma**: quer ajustar template, mas não consegue iniciar.  
**Causa**: `qm template` tornou a VM somente-leitura.  
**Solução**: clonar como VM normal, ajustar, reconverter, atualizar `template_vm_id`, destruir antigo.

---

## 12. Boas Práticas

### 12.1 Scripts separados por responsabilidade

- **`01-prepare-image.sh`** → baixa e customiza a imagem (comum a todas as versões)
- **`02-create-template-XX.sh`** → cria a VM com IDs/nomes específicos (por versão)

### 12.2 Sempre validar URL antes de baixar

```bash
curl -sI <URL> | head -5
# Esperado: HTTP/2 200
```

### 12.3 Sempre clonar para teste antes de escalar

Nunca recrie 6 VMs sem antes validar 1 clone.

### 12.4 Convenção de IDs

Adote numeração consistente (8X00 para templates, 9X00 para VMs).

### 12.5 Backup do `.tfstate`

Antes de mudanças grandes, guarde uma cópia do state. O `.tfstate.backup` é o paraquedas.

### 12.6 Documente o "antes vs depois"

Sempre colete baseline antes de corrigir (IP, hostname, cloud-init status) para provar a melhoria.

### 12.7 Root vs sudo

Prefira `sudo` com usuário normal. Evita arquivos com dono `root` no home.

### 12.8 Nunca use `>` no `.gitignore` sem certeza

`>` sobrescreve, `>>` anexa. Use `>>` para complementar.

---


## 13. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **01-Template-Proxmox-CloudInit.md** *(este documento)* | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL multi-disco |

---

## 14. Troubleshooting — Timeout e Resíduos no Storage

> 🎯 **Seção dedicada aos problemas mais comuns** que aparecem em ambientes Proxmox com Terraform.

### 14.1 Sintoma: "disk image already exists"

**Mensagem de erro:**

```
Error: VM clone
task "UPID:..." failed to complete with exit code: clone failed: 
disk image '/mnt/pve/<STORAGE>/images/<VM_ID>/vm-<VM_ID>-cloudinit.qcow2' already exists
```

**O que significa**: o Proxmox tentou criar o disco de uma VM, mas **encontrou um arquivo com o mesmo nome** já existente.

**Por quê acontece**:

| Causa | Descrição |
|-------|-----------|
| **Timeout na criação** | Terraform desiste, Proxmox continua e cria o disco |
| **Apply interrompido** | Você deu `Ctrl+C` ou a conexão SSH caiu |
| **Resíduos antigos** | Tentativa anterior falhou e deixou arquivos órfãos |
| **Destroy incompleto** | `qm destroy` falhou, mas o state foi limpo |
| **Kill do processo** | Terraform foi morto, mas o `qmclone` continuou |

### 14.2 Como Diagnosticar

**Passo 1 — Ver as VMs ativas no Proxmox:**

```bash
qm list | grep -E "docker-(swarm|worker)"
```

**Passo 2 — Ver as pastas no storage:**

```bash
ls -la /mnt/pve/<STORAGE>/images/
```

**Passo 3 — Ver o que o Terraform conhece:**

```bash
terraform state list | grep docker_environment | sort
```

**Passo 4 — Comparar os três:**

| Storage tem pasta? | `qm list` mostra VM? | State tem recurso? | Situação |
|-------------------|---------------------|--------------------| ---------|
| ❌ Não | ❌ Não | ❌ Não | ✅ Tudo limpo |
| ✅ Sim | ❌ Não | ❌ Não | ⚠️ **Órfão** — precisa remover |
| ✅ Sim | ✅ Sim | ✅ Sim | ✅ Tudo OK |
| ✅ Sim | ✅ Sim | ❌ Não | ⚠️ VM existe mas não está no state |
| ❌ Não | ❌ Não | ✅ Sim | ⚠️ State inconsistente |

### 14.3 Como Resolver

#### Cenário A — Resíduos órfãos (mais comum)

**Sintoma**: pastas no storage **sem** VMs correspondentes no `qm list`.

**Solução**:

```bash
# 1. Confirme que NÃO há VM ativa com esse ID
qm list | grep <VM_ID>

# 2. Se não há VM, remova a pasta
sudo rm -rf /mnt/pve/<STORAGE>/images/<VM_ID>/

# 3. Confirme a remoção
ls /mnt/pve/<STORAGE>/images/ | grep <VM_ID> || echo "✅ Removido"
```

**Depois**:

```bash
# 4. Gere um novo plano (só do que falta)
terraform plan -out=tfplan2

# 5. Revise o plano
terraform show tfplan2 | grep -E "Plan:|will be created"

# 6. Aplique
terraform apply -parallelism=1 tfplan2
```

#### Cenário B — VM existe mas não está no state

**Sintoma**: `qm list` mostra a VM, mas `terraform state list` não.

**Solução**:

```bash
# Importe o recurso para o state
terraform import \
  'proxmox_virtual_environment_vm.docker_environment["docker-worker-01"]' \
  <VM_ID>
```

Depois:

```bash
terraform plan    # deve mostrar "0 to add" para essa VM
```

#### Cenário C — State com recurso mas VM não existe

**Sintoma**: `terraform state list` mostra o recurso, mas `qm list` não.

**Solução**:

```bash
# Remova do state (não afeta o Proxmox, já que a VM não existe)
terraform state rm \
  'proxmox_virtual_environment_vm.docker_environment["docker-worker-01"]'
```

Depois:

```bash
terraform plan    # deve mostrar "1 to add"
terraform apply -parallelism=1
```

### 14.4 Prevenção

**1. Sempre use `-parallelism=1` em hosts modestos:**

```bash
terraform apply -parallelism=1 tfplan
```

**2. Timeouts generosos no `main.tf`:**

```hcl
resource "proxmox_virtual_environment_vm" "docker_environment" {
  # ...
  timeout_create  = 3600   # 60 min
  timeout_clone   = 3600   # 60 min
  timeout_migrate = 1800   # 30 min
}
```

**3. Após qualquer `destroy`, verifique o storage:**

```bash
qm destroy <VM_ID>
ls /mnt/pve/<STORAGE>/images/<VM_ID>/ 2>&1    # deve dar "No such file"
```

**4. Auditoria periódica de órfãos:**

```bash
#!/bin/bash
# Lista pastas no storage que NÃO têm VM correspondente
for dir in /mnt/pve/<STORAGE>/images/*/; do
  id=$(basename "$dir")
  qm status "$id" &>/dev/null || echo "⚠️ Órfão: $id"
done
```

**5. Nunca interrompa um `apply` em andamento:**

Se precisar parar, aguarde terminar ou **saiba que vai deixar resíduos** que exigirão limpeza.

**6. Use `plan -out` antes de todo `apply`:**

```bash
terraform plan -out=tfplan
terraform show tfplan | head -50    # revise!
terraform apply tfplan
```

### 14.5 Lição Aprendida

> 🥇 **Timeout no Terraform não significa que a operação falhou no Proxmox.**
> 
> O Terraform desiste, mas o Proxmox continua a tarefa. Resultado: VM criada, mas state não atualizado.
> 
> **Sempre verifique o estado real antes de agir.**

---

## 🧠 Lições Aprendidas

1. **`cloud-init.disabled` é o bug silencioso** — sem removê-lo, o Terraform aplica config em vão.
2. **`cloud-init clean --logs --seed`** — o `--seed` é essencial para limpar o estado.
3. **Zerar hostname, netplan, SSH keys e machine-id** — cada clone precisa nascer único.
4. **`cloud-initramfs-growroot`** — sem ele, o disco não expande.
5. **`iothread` + `virtio-scsi-single`** — resolve contenção de I/O em hosts com várias VMs.
6. **Template é imutável** — ajustes exigem clonar, ajustar, reconverter.
7. **Validar com clone antes de escalar** — 1 VM testada evita 6 VMs quebradas.
8. **Convenção de IDs** — organização evita conflitos e facilita scripts.
9. **Sempre backup antes de mudar** — `cp arquivo arquivo.bak` é barato.
10. **Documentar depois de validar** — o documento reflete o que funcionou, não teoria.
11. **Timeout no Terraform ≠ falha no Proxmox** — verifique o estado real antes de agir.
12. **Resíduos no storage são silenciosos** — audite periodicamente.

---

*Documento gerado em 01/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
