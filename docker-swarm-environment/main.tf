# =========================================================================
# Locals — Define o Servidor NFS, Managers e Workers
# =========================================================================
locals {
  # Servidor NFS Dedicado (swm-nfs-01 -> IP 10.0.39.30, VM ID 9030)
  swarm_nfs = {
    "swm-nfs-01" = {
      vm_id = var.swarm_nfs_vm_id
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_nfs_ip)}/24"
      role  = "nfs"
    }
  }

  # Managers (docker-swarm-01..03)
  swarm_managers = {
    for idx, name in var.swarm_managers : name => {
      vm_id = var.swarm_manager_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_manager_ip_start + idx)}/24"
      role  = "manager"
    }
  }

  # Workers (docker-worker-01..03)
  swarm_workers = {
    for idx, name in var.swarm_workers : name => {
      vm_id = var.swarm_worker_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_worker_ip_start + idx)}/24"
      role  = "worker"
    }
  }

  # Unifica todos os nós em um único mapa para o resource block
  docker_nodes = merge(local.swarm_nfs, local.swarm_managers, local.swarm_workers)
}

# =========================================================================
# Recurso de Provisionamento das VMs no Proxmox
# =========================================================================
resource "proxmox_virtual_environment_vm" "docker_environment" {
  for_each    = local.docker_nodes
  name        = each.key
  description = "VM ${each.value.role} do ambiente Docker Swarm - provisionada via Terraform"
  tags        = ["terraform", "ubuntu-26", "docker-swarm", each.value.role, "ansible"]
  node_name   = var.target_node
  vm_id       = each.value.vm_id

  timeout_create  = 3600
  timeout_clone   = 3600
  timeout_migrate = 1800

  agent {
    enabled = true
  }

  cpu {
    cores   = tonumber(var.vm_cores)
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = tonumber(var.vm_memory)
  }

  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = tonumber(var.vm_disk_size)
    ssd          = true
    discard      = "on"
  }

  clone {
    vm_id = tonumber(var.template_vm_id)
    full  = false
  }

  network_device {
    bridge = var.vm_bridge
  }

  initialization {
    datastore_id = var.vm_storage_id
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.vm_gateway
      }
    }
    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }
}
