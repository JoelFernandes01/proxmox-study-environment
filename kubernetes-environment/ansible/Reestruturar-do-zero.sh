ssh -i ~/.ssh/id_terraform root@10.0.39.5 'for id in {9400..9408}; do qm stop $id 2>/dev/null; qm destroy $id --purge; done'

ssh -i ~/.ssh/id_terraform root@10.0.39.5 'for id in {11400..11408}; do new_id=$((id-2000)); name=$(qm config $id | awk "/^name:/{print \$2}"); qm clone $id $new_id --full --storage storage-vms --name "${name}" && qm start $new_id; done'

for ip in 10.0.39.{40..45} 10.0.39.{61..63} 10.0.39.70; do ssh-keygen -R $ip 2>/dev/null; ssh-copy-id -i ~/.ssh/id_terraform.pub -o StrictHostKeyChecking=no connect@$ip; done

ansible all -i inventory.yml -m ping

ansible-playbook -i inventory.yml playbooks/00-base/00-prepara-so.yml
ansible all -i inventory.yml -a "swapon -s" --become
ansible all -i inventory.yml -a "systemctl is-active containerd" --become

ansible-playbook -i inventory.yml playbooks/01-storage/01-configura-nfs-server.yml

ansible-playbook -i inventory.yml playbooks/02-loadbalancer/02-configura-keepalived.yml

ansible-playbook -i inventory.yml playbooks/02-loadbalancer/03-configura-haproxy.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/04-prepara-k8s-prereqs.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/05-init-control-plane-01.yml
ssh connect@10.0.39.43 "sudo ls -lha /etc/kubernetes/"
ssh connect@10.0.39.43 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"
ssh connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf | grep server"

ansible-playbook -i inventory.yml playbooks/03-kubernetes/06-gera-tokens-join.yml
ssh connect@10.0.39.43 "sudo kubeadm token list"
ssh connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf | grep server"
ssh connect@10.0.39.43 "sudo kubeadm token list --kubeconfig=/etc/kubernetes/admin.conf"

ansible-playbook -i inventory.yml playbooks/02-loadbalancer/03-configura-haproxy.yml
ssh connect@10.0.39.43 "sudo kubeadm token list --kubeconfig=/etc/kubernetes/admin.conf"
ssh connect@10.0.39.43 "sudo kubeadm token list"

ansible-playbook -i inventory.yml playbooks/03-kubernetes/06-gera-tokens-join.yml
ansible-playbook -i inventory.yml playbooks/03-kubernetes/07-join-control-planes.yml

ssh -i ~/.ssh/id_terraform connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
kubectl get pods -A
kubectl get nodes 

ansible-playbook -i inventory.yml playbooks/03-kubernetes/08-join-workers.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/09-instala-cni-calico.yml
kubectl get pods -A -o wide -w

ansible-playbook -i inventory.yml playbooks/03-kubernetes/10-instala-nfs-provisioner.yml
kubectl get pods -A -o wide 

ansible-playbook -i inventory.yml playbooks/03-kubernetes/11-instala-metrics-server.yml

grep -rn "admin-local.conf" playbooks/

ansible-playbook -i inventory.yml playbooks/03-kubernetes/12-instala-metallb.yml

ssh connect@10.0.39.43 "kubectl get ipaddresspools.metallb.io -n metallb-system"

ssh connect@10.0.39.43 "helm repo add metallb [suspicious link removed] && helm repo update"

ansible-playbook -i inventory.yml playbooks/03-kubernetes/13-instala-traefik-ingress.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/14-instala-cert-manager.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/15-configura-cluster-issuer-ca.yml

ansible-playbook -i inventory.yml playbooks/03-kubernetes/16-deploy-aplicacao-teste-https.yml

ansible-playbook -i inventory.yml playbooks/04-management/16-valida-cluster-k8s-e2e.yml