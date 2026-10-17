### 💾 Doc 11 — Operações de Backup e DR
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar as estratégias de backup do estado do cluster e das VMs no Proxmox VE.

---

#### 1. Backup do Estado do Cluster
O backup do banco do cluster é realizado periodicamente a partir do nó de controle principal.

#### 2. Snapshots no Proxmox VE
- **Rotina Recomendada**: Snapshots diários em nível de VM para as IDs 9400 a 9408.
- **Modo**: Snapshot sem pausa das VMs.
