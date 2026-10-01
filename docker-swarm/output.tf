# =========================================================================
output "docker_nodes_summary" {
  description = "Resumo de todas as VMs do Docker Swarm (nome, VM ID, IP, role)"
  value = {
    for name, vm in proxmox_virtual_environment_vm.docker_environment :
    name => {
      vm_id = vm.vm_id
      ip    = local.docker_nodes[name].ip
      role  = local.docker_nodes[name].role
    }
  }
}

# Uso: terraform output -raw ansible_inventory > ansible/inventory.ini
# =========================================================================
output "ansible_inventory" {
  description = "Inventário Ansible no formato INI"
  value = templatefile("${path.module}/templates/inventory.tpl", {
    managers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment :
      name => local.docker_nodes[name].ip
      if local.docker_nodes[name].role == "manager"
    }
    workers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment :
      name => local.docker_nodes[name].ip
      if local.docker_nodes[name].role == "worker"
    }
    vm_user = var.vm_user
  })
}