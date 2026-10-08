# 🚀 Doc 12 — Preparando Melhor seu Proxmox

> **Autor:** Joel Fernandes  
> **Data:** 07/10/2026  
> **Objetivo:** Documentar as **melhores práticas** para instalar e configurar um host Proxmox VE, aplicando otimizações de **performance**, **segurança** e **profissionalismo** desde o início.  
> **Pré-requisito:** Host zerado, hardware compatível, acesso à BIOS/iDRAC.

---

## 📋 Sumário

1. [Visão Geral](#1-visão-geral)
2. [Hardware e Ambientes](#2-hardware-e-ambientes)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Instalação do Proxmox](#4-instalação-do-proxmox)
5. [Configuração Pós-Instalação](#5-configuração-pós-instalação)
6. [Storage LVM-Thin](#6-storage-lvm-thin)
7. [Rede](#7-rede)
8. [Segurança](#8-segurança)
9. [Performance](#9-performance)
10. [Backup com Veeam](#10-backup-com-veeam)
11. [Monitoramento](#11-monitoramento)
12. [Templates e Cloud-Init](#12-templates-e-cloud-init)
13. [Boas Práticas](#13-boas-práticas)
14. [Troubleshooting](#14-troubleshooting)
15. [Referências Cruzadas](#15-referências-cruzadas)

---

## 1. Visão Geral

### 1.1 Objetivo

Instalar e configurar **2 hosts Proxmox VE** (`des` e `prd`) do **zero**, aplicando:

- ✅ **Performance**: LVM-Thin, I/O scheduler, CPU governor
- ✅ **Segurança**: 2FA, Fail2ban, firewall, SSH hardening
- ✅ **Profissionalismo**: Backup (Veeam), monitoramento, documentação

### 1.2 Ambientes

| Host | Propósito | IP | Domínio |
|------|-----------|-----|---------|
| **`des`** | Desenvolvimento | `10.0.39.5` | `des.nverse.local` |
| **`prd`** | Produção | `10.0.39.7` | `prd.nverse.local` |

### 1.3 Ordem de Execução

```
1. Instalar Proxmox (ISO oficial)
2. Configurar repositórios (no-subscription)
3. Atualizar sistema
4. Criar LVM-Thin (disco de dados)
5. Configurar rede (bridges)
6. Aplicar segurança (SSH, 2FA, firewall)
7. Otimizar performance (kernel, I/O, CPU)
8. Configurar backup (Veeam)
9. Monitoramento
10. Templates e cloud-init
```

---

## 2. Hardware e Ambientes

### 2.1 Dell R410 (`des`)

| Item | Valor |
|------|-------|
| **CPU** | 2x Intel Xeon (R410) |
| **RAM** | 32 GB |
| **SSD** | 500 GB (sistema) |
| **HD** | 3 TB SATA (dados) |
| **Rede** | 1 GbE |
| **iDRAC** | ✅ Sim |
| **Uso** | Desenvolvimento |
| **IP** | `10.0.39.5` |
| **Hostname** | `des.nverse.local` |

### 2.2 Dell R430 (`prd`)

| Item | Valor |
|------|-------|
| **CPU** | 2x Intel Xeon (R430) |
| **RAM** | 64 GB |
| **SSD** | 256 GB (sistema) |
| **HD** | 1 TB SATA (dados) |
| **Rede** | 1 GbE |
| **iDRAC** | ✅ Sim |
| **Uso** | Produção |
| **IP** | `10.0.39.7` |
| **Hostname** | `prd.nverse.local` |

### 2.3 Inventário de VMs

| Ambiente | Total | Windows | Linux |
|----------|-------|---------|-------|
| **`des`** | ~5 | 3 | 2 |
| **`prd`** | ~5 | 3 | 2 |

---

## 3. Pré-requisitos

### 3.1 Hardware

- ✅ **CPU**: 64-bit com suporte a virtualização (VT-x / AMD-V)
- ✅ **RAM**: mínimo 8 GB (recomendado 32 GB+)
- ✅ **Disco**: SSD para sistema + HD/SSD para dados
- ✅ **Rede**: 1 GbE (recomendado 10 GbE para produção)

### 3.2 BIOS/UEFI

- ✅ **Virtualização**: habilitada (VT-x / AMD-V)
- ✅ **VT-d / IOMMU**: habilitada (para passthrough)
- ✅ **Boot mode**: UEFI (recomendado) ou Legacy
- ✅ **iDRAC**: configurado (IP, usuário, senha)

### 3.3 Rede

- ✅ **IP fixo** para o host
- ✅ **Gateway** configurado
- ✅ **DNS** configurado
- ✅ **Switch** com portas disponíveis

---

## 4. Instalação do Proxmox

### 4.1 Download da ISO

- **URL oficial**: https://www.proxmox.com/en/downloads
- **Versão recomendada**: Proxmox VE 9.x

### 4.2 Criar Pendrive Bootável

```bash
# Linux
dd if=proxmox-ve_9.x.iso of=/dev/sdX bs=1M status=progress
```

### 4.3 Instalação

1. **Boot** pelo pendrive (F11/F12 na Dell)
2. **Escolher** "Install Proxmox VE"
3. **Aceitar** o EULA
4. **Escolher** o disco de destino (SSD do sistema)
5. **Configurar**:
   - **Country**: Brazil
   - **Time zone**: America/Sao_Paulo
   - **Keyboard**: Portuguese (Brazil)
6. **Configurar** senha do root
7. **Configurar** rede:
   - **Hostname**: `des.nverse.local`
   - **IP**: `10.0.39.5/24`
   - **Gateway**: `10.0.39.1`
   - **DNS**: `10.0.39.1` (ou `8.8.8.8`)
8. **Escolher** filesystem:
   - **ext4** (recomendado para SSD) ✅
   - **ZFS** (se quiser snapshots nativos)
9. **Instalar** e **reiniciar**

---

## 5. Configuração Pós-Instalação

### 5.1 Remover Repositório Enterprise

```bash
# Remover o repositório enterprise (pago)
rm /etc/apt/sources.list.d/pve-enterprise.list

# Adicionar o repositório no-subscription (grátis)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
```

### 5.2 Atualizar o Sistema

```bash
apt update
apt dist-upgrade -y
apt autoremove -y
```

### 5.3 Remover Aviso de Subscrição

```bash
# Remover o popup de "no valid subscription"
sed -i "s/NotFound/Active/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

---

## 6. Storage LVM-Thin

### 6.1 Verificar Discos

```bash
lsblk
```

**Esperado**:
```
sda (SSD) → sistema
sdb (HD)  → dados (a formatar)
```

### 6.2 Criar LVM-Thin no Disco de Dados

```bash
# Remover partições
wipefs -a /dev/sdb

# Criar PV
pvcreate /dev/sdb

# Criar VG
vgcreate storage-vms /dev/sdb

# Criar Thin Pool
lvcreate -l 100%FREE --thinpool data storage-vms
```

### 6.3 Adicionar Storage no Proxmox

```bash
pvesm add lvmthin storage-vms --vgname storage-vms --thinpool data --content images,rootdir
```

### 6.4 Verificar

```bash
pvesm status
```

**Esperado**:
```
local               dir      active
storage-vms         lvmthin  active
```

### 6.5 Mover Templates para o LVM-Thin

```bash
# Mover template 8000
qm move_disk 8000 scsi0 storage-vms --delete 1
qm move_disk 8000 ide2 storage-vms --delete 1

# Mover template 8100
qm move_disk 8100 scsi0 storage-vms --delete 1
qm move_disk 8100 ide2 storage-vms --delete 1
```

---

## 7. Rede

### 7.1 Configurar Bridge (`vmbr0`)

```bash
nano /etc/network/interfaces
```

**Conteúdo**:
```
auto lo
iface lo inet loopback

auto eno1
iface eno1 inet manual

auto vmbr0
iface vmbr0 inet static
    address 10.0.39.5/24
    gateway 10.0.39.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
```

### 7.2 Aplicar

```bash
systemctl restart networking
ip a show vmbr0
```

### 7.3 (Opcional) VLANs

Se precisar separar tráfego:
```
auto vmbr0.10
iface vmbr0.10 inet static
    address 10.0.10.5/24
    vlan-raw-device vmbr0
```

---

## 8. Segurança

### 8.1 SSH Hardening

**Editar** `/etc/ssh/sshd_config`:

```
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers connect root
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

**Reiniciar**:
```bash
systemctl restart ssh
```

### 8.2 2FA (TOTP) no Proxmox

```bash
# Instalar o pacote
apt install -y libpam-google-authenticator

# Configurar para o usuário root
google-authenticator -t -d -f -r 3 -R 30 -w 3

# Editar PAM
nano /etc/pam.d/common-auth
```

**Adicionar**:
```
auth required pam_google_authenticator.so nullok
```

**Editar** `/etc/ssh/sshd_config`:
```
KbdInteractiveAuthentication yes
UsePAM yes
```

**Reiniciar**:
```bash
systemctl restart ssh
```

### 8.3 Fail2ban

```bash
apt install -y fail2ban
```

**Criar** `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s

[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 3600
```

**Criar** `/etc/fail2ban/filter.d/proxmox.conf`:

```ini
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
```

**Reiniciar**:
```bash
systemctl restart fail2ban
fail2ban-client status
```

### 8.4 Firewall (Proxmox)

**Via GUI**: Datacenter → Firewall → Add

**Regras recomendadas**:
| Direção | Ação | Porta | Comentário |
|---------|------|-------|------------|
| IN | ACCEPT | 22 | SSH |
| IN | ACCEPT | 8006 | Proxmox GUI |
| IN | ACCEPT | 3128 | SPICE |
| IN | ACCEPT | 5900-5999 | VNC |
| IN | DROP | — | Todo o resto |

---

## 9. Performance

### 9.1 CPU Governor

```bash
apt install -y cpufrequtils

# Ver o governor atual
cpufreq-info | grep "current policy"

# Mudar para performance
cpufreq-set -g performance
```

**Persistir**:
```bash
echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
systemctl restart cpufrequtils
```

### 9.2 I/O Scheduler

**Para SSD** (NVMe/SSD):
```bash
echo "none" > /sys/block/sda/queue/scheduler
```

**Para HD** (SATA):
```bash
echo "mq-deadline" > /sys/block/sdb/queue/scheduler
```

**Persistir** (via udev):
```bash
cat > /etc/udev/rules.d/60-ioschedulers.rules << 'EOF'
# SSD - none
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
# HD - mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
```

### 9.3 Swappiness

```bash
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p
```

### 9.4 Hugepages (opcional)

```bash
echo "vm.nr_hugepages=1024" >> /etc/sysctl.conf
sysctl -p
```

### 9.5 Kernel Params

```bash
nano /etc/default/grub
```

**Adicionar**:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

**Atualizar**:
```bash
update-grub
reboot
```

---

## 10. Backup com Veeam

### 10.1 Instalar o Veeam Backup Appliance

**Opção A** — Appliance Linux:
- Baixar o **Veeam Backup Appliance** (OVA)
- Importar no Proxmox
- Configurar

**Opção B** — Veeam Agent (dentro da VM):
- Instalar o **Veeam Agent** na VM
- Configurar backup para repositório

### 10.2 Configurar Backup

1. **Criar** repositório de backup (NFS, SMB, S3)
2. **Configurar** job de backup
3. **Agendar** (diário, semanal)
4. **Testar** restore

### 10.3 Backup do Proxmox (vzdump)

```bash
# Backup manual de uma VM
vzdump 2001 --storage local --mode snapshot --compress zstd

# Agendar via cron
echo "0 3 * * * root vzdump --all --storage local --mode snapshot --compress zstd --mailnotification failure" > /etc/cron.d/vzdump
```

---

## 11. Monitoramento

### 11.1 Prometheus + Grafana (LXC)

```bash
# Criar LXC no Proxmox
pct create 100 local:vztmpl/debian-12-standard_12.x.tar.zst \
  --hostname prometheus \
  --memory 2048 \
  --cores 2 \
  --rootfs storage-vms:8 \
  --net0 name=eth0,bridge=vmbr0,ip=10.0.39.100/24,gw=10.0.39.1
```

### 11.2 Zabbix (VM)

- Criar VM para o Zabbix Server
- Instalar o Zabbix Agent nas VMs

### 11.3 Alertas

- Configurar alertas no Prometheus
- Configurar notificações (email, Telegram, Slack)

---

## 12. Templates e Cloud-Init

### 12.1 Criar Template

```bash
# Baixar imagem cloud
wget https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img

# Customizar
virt-customize -a ubuntu-26.qcow2 ...

# Criar VM
qm create 8000 ...

# Importar disco
qm importdisk 8000 ubuntu-26.qcow2 local --format qcow2

# Configurar
qm set 8000 --scsihw virtio-scsi-single --scsi0 local:8000/vm-8000-disk-0.qcow2,ssd=1,iothread=1
qm set 8000 --boot order=scsi0
qm resize 8000 scsi0 50G
qm set 8000 --ide2 local:cloudinit
qm template 8000
```

### 12.2 Mover Template para LVM-Thin

```bash
qm move_disk 8000 scsi0 storage-vms --delete 1
qm move_disk 8000 ide2 storage-vms --delete 1
```

### 12.3 Linked Clone

```hcl
# No main.tf
clone {
  vm_id = tonumber(var.template_vm_id)
  full  = false   # ← Linked clone
}
```

---

## 13. Boas Práticas

### 13.1 Convenções de IDs

| Faixa | Uso |
|-------|-----|
| `100-199` | VMs de produção |
| `200-299` | VMs de teste |
| `1000-1999` | Containers LXC |
| `8000-8099` | Templates Ubuntu 26 |
| `8100-8199` | Templates Ubuntu 24 |
| `9000-9099` | Docker Swarm (managers) |
| `9100-9199` | Docker Swarm (workers) |

### 13.2 Nomenclatura

- **Hostname**: `funcao-ambiente` (ex: `docker-swarm-01`)
- **Tags**: `terraform`, `ubuntu-26`, `docker-swarm`, `role`
- **Descrição**: propósito da VM

### 13.3 Documentação

- ✅ **Doc 01-11** (projeto)
- ✅ **README.md** (índice)
- ✅ **Git** (versionamento)
- ✅ **Backup** (Veeam)

### 13.4 Versionamento

```bash
git add .
git commit -m "feat: descrição clara"
git push origin main
```

---

## 14. Troubleshooting

### 14.1 Proxmox não sobe após instalação

**Causa**: GRUB/UEFI mal configurado.  
**Solução**: reinstalar com modo Legacy ou ajustar o boot na BIOS.

### 14.2 Rede não funciona

**Causa**: bridge não configurada.  
**Solução**: verificar `/etc/network/interfaces` e reiniciar networking.

### 14.3 LVM-Thin com erro

**Causa**: disco não limpo.  
**Solução**: `wipefs -a /dev/sdb` antes de `pvcreate`.

### 14.4 VM com timeout no clone

**Causa**: full clone lento.  
**Solução**: usar **linked clone** (`full = false`) + **LVM-Thin**.

### 14.5 Backup falha

**Causa**: espaço insuficiente.  
**Solução**: verificar espaço no repositório de backup.

---

## 15. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL multi-disco |
| **[09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md)** | MariaDB multi-disco |
| **[10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md)** | Servidor NFS para persistência |
| **[11-Migracao-Storage-LVM-Thin.md](./11-Migracao-Storage-LVM-Thin.md)** | Migração de storage |
| **12-Preparando-Melhor-seu-Proxmox.md** *(este documento)* | Boas práticas de instalação |
