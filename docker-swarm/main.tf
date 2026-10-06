# =========================================================================
locals {
  # Managers: docker-swarm-01 → IP .100, VM ID 9000
  #           docker-swarm-02 → IP .101, VM ID 9001
  #           docker-swarm-03 → IP .102, VM ID 9002
  swarm_managers = {
    for idx, name in var.swarm_managers :
    name => {
      vm_id = var.swarm_manager_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_manager_ip_start + idx)}/24"
      role  = "manager"
    }
  }

  # Workers: docker-worker-01 → IP .120, VM ID 9010
  #          docker-worker-02 → IP .121, VM ID 9011
  #          docker-worker-03 → IP .122, VM ID 9012
  swarm_workers = {
    for idx, name in var.swarm_workers :
    name => {
      vm_id = var.swarm_worker_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.swarm_worker_ip_start + idx)}/24"
      role  = "worker"
    }
  }

  # Une os dois mapas em um só
  docker_nodes = merge(local.swarm_managers, local.swarm_workers)
}

# =========================================================================
resource "proxmox_virtual_environment_vm" "docker_environment" {
  for_each = local.docker_nodes

  name        = each.key
  description = "VM ${each.value.role} do cluster Docker Swarm - provisionada via Terraform"
  tags        = ["terraform", "ubuntu-26", "docker-swarm", each.value.role, "ansible"]
  node_name   = var.target_node
  vm_id       = each.value.vm_id

  timeout_create  = 3600 # 60 minutos para criação
  timeout_clone   = 3600 # 60 minutos para clonagem
  timeout_migrate = 1800 # 30 minutos para updates

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

  # =========================================================================
  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = tonumber(var.vm_disk_size)
    ssd          = true
    discard      = "on"
  }

  # =========================================================================
  clone {
    vm_id        = tonumber(var.template_vm_id)
    datastore_id = var.vm_storage_id
    full         = false
  }

  network_device {
    bridge = var.vm_bridge
  }

  # =========================================================================
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
