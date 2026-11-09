#!/usr/bin/env bash

# Lista de IDs das 6 VMs que deseja transferir
VMS=(9400 9401 9402 9403 9404 9405)
TARGET_HOST="10.0.39.7"
TARGET_STORAGE="storage_vms"

for vmid in "${VMS[@]}"; do
  echo "==> Transferindo VM $vmid para o host $TARGET_HOST..."
  vzdump $vmid --stdout --compress zstd --mode stop | ssh root@"$TARGET_HOST" "qmrestore - $vmid --storage $TARGET_STORAGE"

  if [ $? -eq 0 ]; then
    echo "==> [OK] VM $vmid migrada com sucesso! Removendo do nó antigo..."
    qm destroy $vmid --purge
  fi
done
