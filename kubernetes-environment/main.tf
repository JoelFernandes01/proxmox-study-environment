# =========================================================================
# Kubernetes — Main
# =========================================================================
# - 2 HAProxy (load balancer)
# - 3 Control Planes (kubeadm)
# - 3 Workers (kubeadm)
# - 1 Template (8000 - Ubuntu 26)
# - Storage LVM-Thin (linked clone)
# =========================================================================

# =========================================================================
# Locals — Define os nós do cluster
# =========================================================================
locals {
  # HAProxy
  k8s_haproxy = {
    for idx, name in var.k8s_haproxy :
    name => {
      vm_id = var.k8s_haproxy_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.k8s_haproxy_ip_start + idx)}/24"
      role  = "haproxy"
    }
  }

  # Control Planes
  k8s_control_planes = {
    for idx, name in var.k8s_control_planes :
    name => {
      vm_id = var.k8s_cp_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.k8s_cp_ip_start + idx)}/24"
      role  = "control-plane"
    }
  }

  # Workers
  k8s_workers = {
    for idx, name in var.k8s_workers :
    name => {
      vm_id = var.k8s_workers_vm_id_start + idx
      ip    = "${cidrhost(var.vm_network_cidr, var.k8s_workers_ip_start + idx)}/24"
      role  = "worker"
    }
  }

  # Storage Server NFS
  k8s_nfs = {
    "k8s-nfs-01" = {
      vm_id     = 9408
      ip        = "10.0.39.70/24"
      role      = "nfs"
      disk_size = 100
    }
  }

  # Une todos
  k8s_nodes = merge(
    local.k8s_haproxy,
    local.k8s_control_planes,
    local.k8s_workers,
    local.k8s_nfs
  )
}

# =========================================================================
# VMs do Kubernetes
# =========================================================================
resource "proxmox_virtual_environment_vm" "k8s" {
  for_each = local.k8s_nodes

  name        = each.key
  description = "VM ${each.value.role} do cluster Kubernetes"
  tags        = ["terraform", "ubuntu-26", "kubernetes", each.value.role, "ansible"]
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

  # Disco principal
  disk {
    datastore_id = var.vm_storage_id
    interface    = "scsi0"
    size         = tonumber(var.vm_disk_size)
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"

  # Clone do template (linked)
  clone {
    vm_id = tonumber(var.template_vm_id)
    full  = false
  }

  network_device {
    bridge = var.vm_bridge
  }

  # Cloud-init
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

  # Console serial
  serial_device {
    device = "socket"
  }
}

# =========================================================================
# Inventário Ansible (YAML)
# =========================================================================
locals {
  ansible_inventory = yamlencode({
    all = {
      hosts = {
        for name, node in local.k8s_nodes :
        name => {
          ansible_host               = trimsuffix(node.ip, "/24")
          ansible_user               = var.vm_user
          ansible_python_interpreter = "/usr/bin/python3"
          ansible_become             = true
        }
      }

      children = {
        k8s_haproxy = {
          hosts = {
            for name, node in local.k8s_haproxy : name => {}
          }
        }
        k8s_control_planes = {
          hosts = {
            for name, node in local.k8s_control_planes : name => {}
          }
        }
        k8s_workers = {
          hosts = {
            for name, node in local.k8s_workers : name => {}
          }
        }
        k8s_nfs = {
          hosts = {
            for name, node in local.k8s_nfs : name => {}
          }
        }
      }
    }
  })
}

resource "local_file" "ansible_inventory" {
  content  = local.ansible_inventory
  filename = "${path.module}/ansible/inventory.yml"
}

# =========================================================================
# Outputs
# =========================================================================
output "k8s_haproxy_ips" {
  description = "IPs dos HAProxy"
  value       = { for name, node in local.k8s_haproxy : name => node.ip }
}

output "k8s_control_planes_ips" {
  description = "IPs dos Control Planes"
  value       = { for name, node in local.k8s_control_planes : name => node.ip }
}

output "k8s_workers_ips" {
  description = "IPs dos Workers"
  value       = { for name, node in local.k8s_workers : name => node.ip }
}

output "k8s_nfs_ips" {
  description = "IP do Servidor NFS"
  value       = { for name, node in local.k8s_nfs : name => node.ip }
}

output "k8s_nodes_summary" {
  description = "Resumo de todos os nós"
  value = {
    for name, node in local.k8s_nodes :
    name => {
      vm_id = node.vm_id
      ip    = node.ip
      role  = node.role
    }
  }
}
