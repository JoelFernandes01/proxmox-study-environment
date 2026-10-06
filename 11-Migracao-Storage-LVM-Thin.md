# 🗄️ Doc 11 — Migração de Storage `dir` para `LVM-Thin`

> **Autor:** Joel Fernandes  
> **Data:** 06/10/2026  
> **Objetivo:** Documentar a migração do storage `storage-vms` do tipo `dir` (qcow2 em ext4) para `LVM-Thin` (bloco), visando melhorar a performance de I/O das VMs, incluindo tratamento de discos com setores defeituosos e limpeza de resíduos.  
> **Pré-requisito:** Proxmox VE 9.x, disco `/dev/sdb` disponível, VMs paradas.

---

## 📋 Sumário

1. [Motivação](#1-motivação)
2. [Arquitetura Antes e Depois](#2-arquitetura-antes-e-depois)
3. [Estado Inicial](#3-estado-inicial)
4. [Etapa 1 — Migrar VM 2001 para o `local`](#4-etapa-1--migrar-vm-2001-para-o-local)
5. [Etapa 2 — Migrar discos essenciais](#5-etapa-2--migrar-discos-essenciais)
6. [Etapa 3 — Remover `unused`](#6-etapa-3--remover-unused)
7. [Etapa 4 — Desmontar o `storage-vms`](#7-etapa-4--desmontar-o-storage-vms)
8. [Etapa 5 — Formatar o `/dev/sdb` como LVM-Thin](#8-etapa-5--formatar-o-devsdb-como-lvm-thin)
9. [Etapa 6 — Criar o novo storage `storage-vms`](#9-etapa-6--criar-o-novo-storage-storage-vms)
10. [Etapa 7 — Mover VM 2001 de volta](#10-etapa-7--mover-vm-2001-de-volta)
11. [Etapa 8 — Validar a VM](#11-etapa-8--validar-a-vm)
12. [Etapa 9 — Limpeza de Resíduos](#12-etapa-9--limpeza-de-resíduos)
13. [Etapa 10 — Comparativo Antes vs Depois](#13-etapa-10--comparativo-antes-vs-depois)
14. [Fluxo Completo](#14-fluxo-completo)
15. [Próximos Passos](#15-próximos-passos)
16. [Referências Cruzadas](#16-referências-cruzadas)

---

## 1. Motivação

O storage `storage-vms` estava configurado como tipo **`dir`** (diretório), onde os discos das VMs são arquivos `.qcow2` sobre um filesystem **ext4**.

**Problemas identificados**:

| # | Problema | Impacto |
|---|----------|---------|
| 1 | I/O lento (camada extra de filesystem) | Clone de VM ~3 min |
| 2 | Sem suporte nativo a linked clones | Full clone (copia 50 GB) |
| 3 | Sem suporte a snapshots eficientes | Snapshots custosos |
| 4 | `terraform apply` demorava ~20 min para 6 VMs | Lentidão no provisionamento |
| 5 | 592 setores defeituosos no disco `/dev/sdb` | Risco de perda de dados |

**Solução**: migrar para **LVM-Thin** (armazenamento em bloco), que oferece:
- ✅ Performance superior de I/O
- ✅ Suporte nativo a snapshots e linked clones
- ✅ Melhor uso do espaço (thin provisioning)

---

## 2. Arquitetura Antes e Depois

### Antes (`dir`)

```
/dev/sdb (2.7 TB)
  └── sdb1 (ext4) → /mnt/pve/storage-vms
        ├── 2001/vm-2001-disk-2.qcow2   (50 GB)
        ├── 2001/vm-2001-disk-3.qcow2   (100 GB)
        └── 8100/...                     (template duplicado)
```

### Depois (`LVM-Thin`)

```
/dev/sdb (2.7 TB)
  └── LVM (VG: storage-vms)
        └── LVM-Thin (pool: data)
              ├── vm-2001-disk-0         (bloco)
              ├── vm-2001-disk-1         (bloco)
              └── vm-XXXX-disk-0         (VMs do Swarm)
```

---

## 3. Estado Inicial

### VMs Existentes

| VM | Nome | Status | Disco | Localização |
|----|------|--------|-------|-------------|
| `2001` | Windows-Server-2026-ADS-SERVER | stopped | 150 GB (50+100) | `storage-vms` |
| `8000` | ubuntu-server-26-template | stopped | 50 GB | `local` |
| `8100` | ubuntu-server-24-template | stopped | 50 GB | `local` |

### Storage `storage-vms`

```
/mnt/pve/storage-vms/images/
├── 2001/    ← VM Windows Server (150 GB)
└── 8100/    ← cópia duplicada do template (2.3 GB)
```

### Espaço no `local`

```
/dev/mapper/pve-root  431G  47G  366G  12% /
```

**Tradução**: 366 GB livres no `local` (SSD do sistema).

### Discos da VM 2001

```
virtio0: storage-vms:2001/vm-2001-disk-2.qcow2 (50 GB)
virtio1: storage-vms:2001/vm-2001-disk-3.qcow2 (100 GB)
```

---

## 4. Etapa 1 — Migrar VM 2001 para o `local`

**Motivo**: liberar o `storage-vms` para ser formatado como LVM-Thin.

**Pré-requisito**: VM 2001 parada (`stopped`).

### 4.1 Mover o disco `virtio0`

```bash
qm move_disk 2001 virtio0 local --delete 1
```

**O que faz**:
- Copia o disco `virtio0` (50 GB) para o `local`
- Atualiza a config da VM
- Remove o disco original do `storage-vms`

### 4.2 Mover o disco `virtio1`

```bash
qm move_disk 2001 virtio1 local --delete 1
```

**O que faz**: idem para o disco `virtio1` (100 GB).

### 4.3 Verificar

```bash
qm config 2001 | grep -E 'virtio|scsi'
```

**Esperado**:

```
virtio0: local:2001/vm-2001-disk-0.qcow2,cache=directsync,iothread=1,size=50G
virtio1: local:2001/vm-2001-disk-1.qcow2,iothread=1,size=100G
```

### 4.4 Verificar espaço no `local`

```bash
df -h /var/lib/vz
```

**Esperado**:

```
Filesystem            Size  Used Avail Use% Mounted on
/dev/mapper/pve-root  431G  197G  217G  48% /
```

**Tradução**: 197 GB usados (47 do sistema + 150 da VM).

---

### 4.5 ⚠️ Alternativa — Cópia com `ddrescue` (discos com defeito)

**Quando usar**: se o `qm move_disk` falhar com **`Input/output error`**, significa que o disco tem **setores defeituosos**.

**Exemplo de erro**:

```
qemu-img: error while reading at byte 778387456: Input/output error
storage migration failed: copy failed: command '/usr/bin/qemu-img convert -p -n -f qcow2 -O qcow2 ...' failed
```

**Diagnóstico — Verificar a saúde do disco**:

```bash
smartctl -a /dev/sdb | grep -E 'SMART overall|Reallocated|Current_Pending|Offline_Uncorrectable'
```

**Exemplo de saída com problema**:

```
SMART overall-health self-assessment test result: PASSED
  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
197 Current_Pending_Sector  0x0012   097   097   000    Old_age   Always       -       592
198 Offline_Uncorrectable   0x0010   097   097   000    Old_age   Offline      -       592
```

| Atributo | Valor | Significado |
|----------|-------|-------------|
| `SMART overall` | `PASSED` | Disco ainda funcional |
| `Current_Pending_Sector` | **592** | 🚨 Setores com erro pendente |
| `Offline_Uncorrectable` | **592** | 🚨 Setores irrecuperáveis |

**Tradução**: o disco tem **592 setores defeituosos** (≈ 296 KB de dados irrecuperáveis).

**Solução — Copiar com `ddrescue`**:

O `ddrescue` é uma ferramenta **tolerante a erros** que:
- ✅ **Continua** após erros de I/O
- ✅ **Retenta** os setores com problema (`-r3`)
- ✅ **Gera um mapa** de progresso (pode retomar)
- ✅ **Reporta** os setores defeituosos

#### Passo 1 — Instalar o `ddrescue`

```bash
apt install -y gddrescue
```

#### Passo 2 — Criar o diretório de destino

```bash
mkdir -p /var/lib/vz/images/2001/
```

> ⚠️ **Atenção**: o `qm move_disk` falhou **antes** de criar o diretório. Por isso precisamos criar manualmente.

#### Passo 3 — Rodar o `ddrescue`

```bash
ddrescue -d -r3 \
  /mnt/pve/storage-vms/images/2001/vm-2001-disk-2.qcow2 \
  /var/lib/vz/images/2001/vm-2001-disk-0.qcow2 \
  /tmp/ddrescue-disk2.map
```

**Parâmetros**:

| Flag | O que faz |
|------|-----------|
| `-d` | Acesso **direto** ao disco (ignora cache) |
| `-r3` | **3 tentativas** nos setores com erro |
| `<mapfile>` | Salva o **progresso** (pode retomar) |

**Tempo estimado**: ~5-15 min (dependendo dos erros).

**Saída esperada**:

```
GNU ddrescue 1.29
Press Ctrl-C to interrupt
     ipos:   XXXXX MB, non-trimmed:   XXXXX B,  current rate:  XX MB/s
     opos:   XXXXX MB, non-scraped:   XXXXX B,  average rate:  XX MB/s
non-tried:   XXXXX B,  bad-sector:   XXXXX B,    error rate:  XXX B/s
  rescued:   XXXXX MB,   bad areas:         X,        run time:  XXm XXs
```

**Interpretação**:

| Campo | Significado |
|-------|-------------|
| `rescued` | Bytes copiados com sucesso |
| `bad-sector` | Bytes não copiados (erros) |
| `non-tried` | Bytes ainda não tentados |
| `error rate` | Taxa de erros |

**Resultado do nosso caso**:

```
rescued:    53695 MB
pct rescued: 99.99%
bad-sector:   73728 B
bad areas:    15
read errors:  591
run time:      1h 0m 7s
Finished
```

**Tradução**: **99,99% recuperado**, 72 KB irrecuperáveis.

#### Passo 4 — Verificar o resultado

```bash
ls -lh /var/lib/vz/images/2001/
qemu-img info /var/lib/vz/images/2001/vm-2001-disk-0.qcow2
qemu-img check /var/lib/vz/images/2001/vm-2001-disk-0.qcow2
```

**Saída esperada**:

```
file format: qcow2
virtual size: 50 GiB
corrupt: false          ← ✅ NÃO CORROMPIDO
...
No errors were found on the image.  ← ✅ ZERO ERROS
```

#### Passo 5 — Atualizar a config da VM

```bash
qm set 2001 --virtio0 local:2001/vm-2001-disk-0.qcow2
```

#### Passo 6 — Testar a VM

```bash
qm start 2001
```

> ⚠️ **Atenção**: se a VM **não iniciar**, reverta:
> ```bash
> qm stop 2001
> qm set 2001 --virtio0 storage-vms:2001/vm-2001-disk-2.qcow2,cache=directsync,iothread=1,size=50G
> ```

---

### 4.6 ⚠️ Alerta — Disco com Setores Defeituosos

**Se o disco tem setores defeituosos** (`Current_Pending_Sector > 0`):

| Ação | Prioridade |
|------|------------|
| ✅ **Backup imediato** dos dados | 🔴 **CRÍTICA** |
| ✅ **Não escrever mais** no disco | 🔴 **CRÍTICA** |
| ✅ **Planejar substituição** | 🟡 Alta |
| ⚠️ **Migrar com `ddrescue`** | 🟡 Média |
| ❌ **Ignorar o problema** | 🚫 Nunca |

**Sinais de que o disco está morrendo**:

```bash
dmesg | grep -i 'I/O error\|ata.*error\|sd 1' | tail -20
```

**Recomendação**:

- ⚠️ **Disco com setores defeituosos** = **substituir** (não confiar)
- ⚠️ **Usar apenas para dados temporários**
- ⚠️ **Backup constante**

---

### 4.7 Comparativo — `qm move_disk` vs `ddrescue`

| Aspecto | `qm move_disk` | `ddrescue` |
|---------|----------------|------------|
| **Tolerância a erros** | ❌ Falha no primeiro erro | ✅ Continua após erros |
| **Retry** | ❌ Sem retry | ✅ Retenta 3x (`-r3`) |
| **Mapa de progresso** | ❌ Sem | ✅ Gera mapa (`/tmp/*.map`) |
| **Retomada** | ❌ Sem | ✅ Pode retomar |
| **Report de erros** | ⚠️ Genérico | ✅ Detalhado (bad-sectors) |
| **Uso** | Discos saudáveis | **Discos com defeito** |

**Regra de ouro**:

> 🥇 **Disco saudável → `qm move_disk`. Disco com defeito → `ddrescue`.**

---

## 5. Etapa 2 — Migrar discos essenciais

**Motivo**: o `efidisk0` e o `tpmstate0` são **essenciais** para o boot UEFI e para o Windows.

### 5.1 Migrar o `efidisk0`

```bash
qm move_disk 2001 efidisk0 local --delete 1
```

**O que faz**: move o EFI Disk (528 KB).

### 5.2 Migrar o `tpmstate0`

```bash
qm move_disk 2001 tpmstate0 local --delete 1
```

**O que faz**: move o TPM State (4 MB).

### 5.3 Verificar

```bash
qm config 2001 | grep -E 'efidisk|tpmstate'
```

**Esperado**:

```
efidisk0: local:2001/vm-2001-disk-2.qcow2,efitype=4m,size=528K
tpmstate0: local:2001/vm-2001-disk-3.qcow2,size=4M,version=v2.0
```

---

## 6. Etapa 3 — Remover `unused`

### 6.1 Verificar os `unused`

```bash
qm config 2001 | grep -iE 'unused|storage-vms'
```

**Saída**:

```
unused0: storage-vms:2001/vm-2001-disk-0.qcow2
unused1: storage-vms:2001/vm-2001-disk-2.qcow2
unused2: storage-vms:2001/vm-2001-disk-3.qcow2
```

### 6.2 Remover os `unused`

```bash
qm set 2001 --delete unused0
qm set 2001 --delete unused1
qm set 2001 --delete unused2
```

> 💡 **`qm set --delete` remove a referência E apaga o arquivo** automaticamente.

### 6.3 Verificar

```bash
qm config 2001 | grep -iE 'unused|storage-vms'
```

**Esperado**: vazio ✅

---

## 7. Etapa 4 — Desmontar o `storage-vms`

### 7.1 Remover do Proxmox

```bash
pvesm remove storage-vms
```

### 7.2 Desmontar

```bash
umount /mnt/pve/storage-vms
```

### 7.3 Verificar

```bash
mount | grep storage-vms || echo "✅ Não está montado"
```

**Esperado**: `✅ Não está montado`

---

## 8. Etapa 5 — Formatar o `/dev/sdb` como LVM-Thin

### 8.1 Remover a tabela de partições

```bash
wipefs -a /dev/sdb
```

**O que faz**: remove **todas as assinaturas** (GPT, ext4, PMBR).

### 8.2 Criar o Physical Volume (PV)

```bash
pvcreate /dev/sdb
```

**O que faz**: prepara o disco para LVM.

**Verificar**:

```bash
pvs
```

**Esperado**:

```
PV         VG  Fmt  Attr PSize    PFree 
/dev/sda3  pve lvm2 a--  <446.13g     0 
/dev/sdb       lvm2 ---    <2.73t <2.73t
```

### 8.3 Criar o Volume Group (VG)

```bash
vgcreate storage-vms /dev/sdb
```

**Verificar**:

```bash
vgs
```

**Esperado**:

```
VG          #PV #LV #SN Attr   VSize    VFree 
pve           1   2   0 wz--n- <446.13g     0 
storage-vms   1   0   0 wz--n-   <2.73t <2.73t
```

### 8.4 Criar o Thin Pool

```bash
lvcreate -l 100%FREE --thinpool data storage-vms
```

**Verificar**:

```bash
lvs
```

**Esperado**:

```
LV   VG          Attr       LSize    Pool Origin Data%  Meta%
root pve         -wi-ao---- <438.13g
swap pve         -wi-ao----    8.00g
data storage-vms twi-a-tz--   <2.73t             0.00   10.43
```

---

## 9. Etapa 6 — Criar o novo storage `storage-vms`

### 9.1 Adicionar o storage no Proxmox

```bash
pvesm add lvmthin storage-vms --vgname storage-vms --thinpool data --content images,rootdir
```

### 9.2 Verificar

```bash
pvesm status
```

**Esperado**:

```
Name               Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
local               dir     active       451604168       208939564       223265488   46.27%
storage-vms     lvmthin     active      2930081792               0      2930081792    0.00%
```

### 9.3 Verificar o `storage.cfg`

```bash
cat /etc/pve/storage.cfg
```

**Esperado**:

```ini
dir: local
    path /var/lib/vz
    content vztmpl,rootdir,iso,images,backup
    shared 0

lvmthin: storage-vms
    thinpool data
    vgname storage-vms
    content images,rootdir
```

---

## 10. Etapa 7 — Mover VM 2001 de volta

### 10.1 Mover os discos de dados

```bash
qm move_disk 2001 virtio0 storage-vms --delete 1
qm move_disk 2001 virtio1 storage-vms --delete 1
```

### 10.2 Mover os discos essenciais

```bash
qm move_disk 2001 efidisk0 storage-vms --delete 1
qm move_disk 2001 tpmstate0 storage-vms --delete 1
```

### 10.3 Verificar

```bash
qm config 2001 | grep -E 'virtio|efidisk|tpmstate'
```

**Esperado**:

```
efidisk0: storage-vms:vm-2001-disk-2,efitype=4m,size=4M
tpmstate0: storage-vms:vm-2001-disk-3,size=4M,version=v2.0
virtio0: storage-vms:vm-2001-disk-0,size=50G
virtio1: storage-vms:vm-2001-disk-1,iothread=1,size=100G
```

> 💡 **Repare**: não tem mais `.qcow2` — agora são **blocos** do LVM.

---

## 11. Etapa 8 — Validar a VM

### 11.1 Iniciar a VM

```bash
qm start 2001
```

### 11.2 Verificar

```bash
qm list | grep 2001
```

**Esperado**:

```
2001 Windows-Server-2026-ADS-SERVER running 8192 50.00 701553
```

**Tradução**: VM rodando com sucesso. ✅

---

## 12. Etapa 9 — Limpeza de Resíduos

Após a migração da VM 2001 e a criação do novo storage LVM-Thin, **resíduos** ficaram no sistema:

### 12.1 Pastas Órfãs no `/mnt/pve/`

**Verificação**:

```bash
ls -lha /mnt/pve/
```

**Saída**:

```
drwxr-xr-x 2 root root 4.0K Sep  9 11:32 backup-vms
drwxr-xr-x 2 root root 4.0K Sep  9 11:35 external-disk
drwxr-xr-x 2 root root 4.0K Aug 19 17:33 storage-vms
```

**Análise**:

| Pasta | Status | O que era |
|-------|--------|-----------|
| `/mnt/pve/storage-vms/` | ⚠️ **Órfã** | Storage `dir` antigo (agora é `lvmthin`) |
| `/mnt/pve/backup-vms/` | ⚠️ **Órfã** | Storage de backup antigo |
| `/mnt/pve/external-disk/` | ⚠️ **Órfã** | Disco externo antigo |

**Verificações antes de remover**:

```bash
# 1. As pastas estão vazias?
ls -lha /mnt/pve/storage-vms/
ls -lha /mnt/pve/backup-vms/
ls -lha /mnt/pve/external-disk/

# 2. As pastas estão montadas?
mount | grep /mnt/pve/

# 3. Algum storage usa essas pastas?
cat /etc/pve/storage.cfg | grep -E 'path|storage-vms|backup-vms|external-disk'
```

**Resultado**:
- ✅ **Todas vazias**
- ✅ **Nenhuma montada**
- ✅ **Nenhum storage usa**

**Remoção**:

```bash
rmdir /mnt/pve/storage-vms/ /mnt/pve/backup-vms/ /mnt/pve/external-disk/
```

> 💡 **`rmdir` é seguro** — só remove se a pasta estiver **vazia**.

**Verificação final**:

```bash
ls -lha /mnt/pve/
```

**Saída**:

```
total 8.0K
drwxr-xr-x 2 root root 4.0K Oct  6 09:52 .
drwxr-xr-x 4 root root 4.0K Aug 19 20:46 ..
```

**Tradução**: pastas removidas. ✅

### 12.2 Storage.cfg Final

**Verificação**:

```bash
cat /etc/pve/storage.cfg
```

**Saída**:

```ini
dir: local
    path /var/lib/vz
    content vztmpl,rootdir,iso,images,backup
    shared 0

lvmthin: storage-vms
    thinpool data
    vgname storage-vms
    content images,rootdir
```

**Tradução**: apenas **2 storages** configurados. **Nenhuma duplicação**. ✅

### 12.3 Status Final dos Storages

```bash
pvesm status
```

**Saída**:

```
Name               Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
local               dir     active       451604168        51629276       380575776   11.43%
storage-vms     lvmthin     active      2930081792        26663744      2903418047    0.91%
```

**Tradução**:
- ✅ **`local`**: só o sistema + templates
- ✅ **`storage-vms`**: VM 2001 + thin provisioning
- ✅ **Zero resíduos**

### 12.4 Checklist de Limpeza

| # | Verificação | Comando | Status |
|---|-------------|---------|--------|
| 1 | **Pastas vazias** | `ls /mnt/pve/` | ✅ |
| 2 | **Nenhuma montada** | `mount \| grep /mnt/pve/` | ✅ |
| 3 | **Nenhum storage usa** | `cat /etc/pve/storage.cfg` | ✅ |
| 4 | **Remover pastas** | `rmdir ...` | ✅ |
| 5 | **Verificar remoção** | `ls /mnt/pve/` | ✅ |
| 6 | **Storage.cfg limpo** | `cat /etc/pve/storage.cfg` | ✅ |
| 7 | **Status OK** | `pvesm status` | ✅ |

---

## 13. Etapa 10 — Comparativo Antes vs Depois

### 13.1 Tabela Comparativa

| Métrica | Ambiente Anterior (`dir`) | Ambiente Novo (`lvmthin`) | Ganho |
|---------|---------------------------|---------------------------|-------|
| **Tipo de storage** | `dir` (qcow2 em ext4) | `lvmthin` (bloco) | ✅ |
| **Espaço usado (total)** | 175 GB | 26.6 GB | **~6.5x menor** |
| **Backups órfãos** | 97 GB | 0 GB | **100%** |
| **Tempo de clone (full)** | ~3 min | ~1 min | **~3x mais rápido** |
| **Tempo de clone (linked)** | ❌ Não suportado | **3 segundos** | **∞** |
| **Tamanho do clone** | 50 GB | **7.7 MB** | **~6500x menor** |
| **Snapshots** | ⚠️ Lentos | ✅ Eficientes | ✅ |
| **Linked clones** | ❌ Não suportado | ✅ **Suportado** | ✅ |
| **Setores defeituosos** | 592 | 592 (mesmo disco) | ⚠️ |

### 13.2 Detalhamento dos Testes

#### Clone de VM

**Antes (`dir`)**:

```bash
$ time qm clone 8000 9999 --name teste --full true
real    3m 20s
```

**Depois (`lvmthin`)**:

```bash
$ time qm clone 8000 9999 --name teste --full false
real    0m 3.064s
```

**Ganho**: **~65x mais rápido** (com linked clone).

#### Espaço de Disco

**Antes (`dir`)**:

```
VM 2001 (150 GB) → 150 GB alocados
Clone (50 GB)    → 50 GB alocados
Total            → 200 GB
```

**Depois (`lvmthin`)**:

```
VM 2001 (150 GB) → 26.6 GB usados (thin)
Clone (50 GB)    → 7.7 MB usados (linked)
Total            → 26.6 GB
```

**Ganho**: **~7.5x menos espaço**.

### 13.3 Vantagens do LVM-Thin

| # | Vantagem | Impacto |
|---|----------|---------|
| 1 | **Thin provisioning** | Espaço alocado sob demanda |
| 2 | **Linked clones** | ~6500x mais rápidos |
| 3 | **Snapshots eficientes** | Rollback rápido |
| 4 | **I/O em bloco** | Performance superior |
| 5 | **Sem overhead de filesystem** | Menos latência |

### 13.4 Desvantagens do LVM-Thin

| # | Desvantagem | Mitigação |
|---|-------------|-----------|
| 1 | **Oversubscription** | Monitorar espaço |
| 2 | **Complexidade** | Documentar bem |
| 3 | **Snapshots dependem do original** | Cuidado ao deletar |
| 4 | **Não conserta defeitos físicos** | Substituir o disco |

---

## 14. Fluxo Completo

```
FASE 1 — Diagnóstico
   ├── ✅ VMs destruídas (2013, 40001, 9000, 9001, 9010)
   ├── ✅ SMART do disco (592 setores defeituosos)
   └── ✅ Estado do storage (sdb com 152 GB residuais)

FASE 2 — Migrar VM 2001 (virtio0 + virtio1) para o local
   ├── ✅ virtio0 (50 GB) — config + disco no local
   ├── ✅ virtio1 (100 GB) — config + disco no local
   └── ✅ VM 2001 rodando (testada)

FASE 3 — Migrar discos essenciais (efidisk0 + tpmstate0)
   ├── ✅ efidisk0 (528 KB)
   └── ✅ tpmstate0 (4 MB)

FASE 4 — Remover unused (config limpa)
   ├── ✅ unused0 removido
   ├── ✅ unused1 removido
   └── ✅ unused2 removido

FASE 5 — Desmontar o storage-vms
   ├── ✅ pvesm remove storage-vms
   └── ✅ umount /mnt/pve/storage-vms

FASE 6 — Formatar o sdb como LVM-Thin
   ├── ✅ wipefs -a /dev/sdb
   ├── ✅ pvcreate /dev/sdb
   ├── ✅ vgcreate storage-vms /dev/sdb
   └── ✅ lvcreate --thinpool data storage-vms

FASE 7 — Criar o novo storage-vms
   └── ✅ pvesm add lvmthin storage-vms

FASE 8 — Mover VM 2001 de volta (LVM-Thin)
   ├── ✅ virtio0 → storage-vms
   ├── ✅ virtio1 → storage-vms
   ├── ✅ efidisk0 → storage-vms
   └── ✅ tpmstate0 → storage-vms

FASE 9 — Validar a VM
   ├── ✅ VM 2001 rodando
   └── ✅ Discos no storage-vms

FASE 10 — Limpeza de Resíduos
   ├── ✅ Pastas órfãs removidas
   ├── ✅ Storage.cfg limpo
   └── ✅ Status OK

FASE 11 — Comparar performance
   ├── ✅ Clone linked: 3s (vs 3 min)
   ├── ✅ Tamanho: 7.7 MB (vs 50 GB)
   └── ✅ Espaço: 26.6 GB (vs 175 GB)
```

---

## 15. Próximos Passos

Após a migração, o próximo passo é **recriar as VMs do Swarm** usando o **novo storage LVM-Thin** e **linked clones**.

**Vantagens esperadas**:

| Item | Antes | Depois |
|------|-------|--------|
| **Tempo de apply** | ~20 min | **~2 min** |
| **Espaço** | 300 GB | **~50 MB** |
| **Snapshots** | ⚠️ | ✅ |

**Plano**:

1. Atualizar o `main.tf` para linked clone (`full = false`)
2. Rodar `terraform apply -parallelism=3`
3. Validar as 6 VMs
4. Rodar Ansible (01, 02, 03, 05)
5. Validar o cluster

---

## 16. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Instalação via Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **[07-Governanca-Git.md](./07-Governanca-Git.md)** | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible
