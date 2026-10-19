[nfs]
%{ for name, ip in nfs ~}
${name} ansible_host=${ip}
%{ endfor ~}

[managers]
%{ for name, ip in managers ~}
${name} ansible_host=${ip}
%{ endfor ~}

[workers]
%{ for name, ip in workers ~}
${name} ansible_host=${ip}
%{ endfor ~}

[swarm:children]
nfs
managers
workers

[swarm:vars]
ansible_user=${vm_user}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
