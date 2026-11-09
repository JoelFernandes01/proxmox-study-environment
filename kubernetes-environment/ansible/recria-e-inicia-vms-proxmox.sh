#!/usr/bin/env bash
# Script para recriar, clonar e iniciar as VMs do Kubernetes no Proxmox VE
# Faixa de origem (Templates): 11400..11408
# Faixa de destino (VMs Clonadas): 9400..9408 (calculado via ID - 2000)

PROXMOX_HOST="10.0.39.5"
SSH_KEY="~/.ssh/id_terraform"

echo "==> Conectando ao Proxmox ($PROXMOX_HOST) e executando a clonagem..."

ssh -i "$SSH_KEY" root@"$PROXMOX_HOST" << 'EOF'
for id in 11400 11401 11402 11403 11404 11405 11406 11407 11408; do
  new_id=$((id - 2000))
  name=$(qm config $id | awk '/^name:/{print $2}')
  clean_name="${name%-template}"
  
  echo "==> Recriando e iniciando VM $new_id ($clean_name) a partir do template $id..."
  qm stop $new_id 2>/dev/null || true
  qm destroy $new_id --purge 2>/dev/null || true
  qm clone $id $new_id --full --storage storage-vms --name "${clean_name}"
  qm start $new_id
done
EOF

echo "==> Processo de clonagem e inicialização concluído no Proxmox VE!"
