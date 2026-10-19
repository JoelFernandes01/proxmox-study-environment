# =========================================================================
# INVENTÁRIO ANSIBLE - DOCKER SWARM
# Gerado automaticamente pelo Terraform
# =========================================================================

[managers]
%{ for name, ip in managers ~}
${name} ansible_host=${trimsuffix(ip, "/24")} ansible_user=${vm_user}
%{ endfor ~}

[workers]
%{ for name, ip in workers ~}
${name} ansible_host=${trimsuffix(ip, "/24")} ansible_user=${vm_user}
%{ endfor ~}

[swarm:children]
managers
workers

[swarm:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
