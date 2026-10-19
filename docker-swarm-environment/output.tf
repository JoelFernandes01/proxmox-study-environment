output "docker_nodes_summary" {
  description = "Resumo de todas as VMs do ambiente Docker Swarm"
  value = {
    for name, vm in proxmox_virtual_environment_vm.docker_environment : name => {
      vm_id = vm.vm_id
      ip    = local.docker_nodes[name].ip
      role  = local.docker_nodes[name].role
    }
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    nfs = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment : name => split("/", local.docker_nodes[name].ip)[0]
      if local.docker_nodes[name].role == "nfs"
    }
    managers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment : name => split("/", local.docker_nodes[name].ip)[0]
      if local.docker_nodes[name].role == "manager"
    }
    workers = {
      for name, vm in proxmox_virtual_environment_vm.docker_environment : name => split("/", local.docker_nodes[name].ip)[0]
      if local.docker_nodes[name].role == "worker"
    }
    vm_user = var.vm_user
  })
  filename = "${path.module}/ansible/inventory/hosts.ini"
}
