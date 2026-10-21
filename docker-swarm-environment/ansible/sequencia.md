terraform destroy -parallelism=1 -auto-approve
time terraform apply -auto-approve

cd ansible

for ip in 30 31 32 33 35 36 37; do ssh-keygen -R 10.0.39.$ip; done
for ip in 30 31 32 33 35 36 37; do ping -c 3 10.0.39.$ip; done
for ip in 30 31 32 33 35 36 37; do ping -c 1 10.0.39.$ip | grep "bytes from"; done

ls -lha 
ansible all -i inventory/hosts.ini -m ping
ansible-playbook -i inventory/hosts.ini playbooks/00-base-ubuntu.yml
ansible-playbook -i inventory/hosts.ini playbooks/01-nfs-server.yml
ssh -i ~/.ssh/id_terraform connect@10.0.39.30 "systemctl status nfs-kernel-server --no-pager"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "showmount -e 10.0.39.30"
ansible-playbook -i inventory/hosts.ini playbooks/02-install-docker.yml
for ip in 31 32 33 35 36 37; do echo "=== IP 10.0.39.$ip ==="; ssh -i ~/.ssh/id_terraform connect@10.0.39.$ip "docker --version && systemctl is-active docker"; done
ansible-playbook -i inventory/hosts.ini playbooks/03-swarm.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-workers.yml
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker node ls"
ansible-playbook -i inventory/hosts.ini playbooks/05-deploy-stacks.yml
watch ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service ls"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service ls"
ssh -i ~/.ssh/id_terraform connect@10.0.39.30 "ls -la /srv/nfs/portainer"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs portainer_portainer --tail 50"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs -f portainer_portainer"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs traefik_traefik --tail 50"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs jenkins-stack_jenkins --tail 50"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs portainer_portainer 2>&1 | grep -i token"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs portainer_portainer"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs portainer_portainer"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service ps portainer_portainer"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh -i ~/.ssh/id_terraform connect@10.0.39.30 "free -h && df -h /srv/nfs/*"
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "mount | grep nfs"
