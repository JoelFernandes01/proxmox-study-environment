time terraform destroy -parallelism=1 -auto-approve
time terraform apply -target='proxmox_virtual_environment_vm.k8s["k8s-nfs-01"]' -parallelism=1 -auto-approve
time terraform apply \
-target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-01"]' \
-target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-02"]' \
-target='proxmox_virtual_environment_vm.k8s["k8s-control-plane-03"]' \
-parallelism=1 -auto-approve
time terraform apply \
-target='proxmox_virtual_environment_vm.k8s["k8s-worker-01"]' \
-target='proxmox_virtual_environment_vm.k8s["k8s-worker-02"]' \
-target='proxmox_virtual_environment_vm.k8s["k8s-worker-03"]' \
-parallelism=1 -auto-approve
time terraform apply \
-target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-01"]' \
-target='proxmox_virtual_environment_vm.k8s["k8s-haproxy-02"]' \
-parallelism=1 -auto-approve
terraform apply -parallelism=1 -auto-approve
cd ansible
cat inventory.yml
for i in {40..45} {60..65} 70; do ssh-keygen -R "10.0.39.$i"; done
for i in {40..45} {60..65} 70; do ssh-keyscan -H "10.0.39.$i" >> ~/.ssh/known_hosts; done
ansible all -i inventory.yml -m ping
ssh -i ~/.ssh/id_terraform connect@10.0.39.43 "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get no

kubectl label node k8s-worker-01 node-role.kubernetes.io/k8s-worker-01=
kubectl label node k8s-worker-02 node-role.kubernetes.io/k8s-worker-02=
kubectl label node k8s-worker-03 node-role.kubernetes.io/k8s-worker-03=

kubectl label node k8s-control-plane-01 node-role.kubernetes.io/control-plane-01=
kubectl label node k8s-control-plane-02 node-role.kubernetes.io/control-plane-02=
kubectl label node k8s-control-plane-03 node-role.kubernetes.io/control-plane-03=

kubectl label node k8s-control-plane-01 node-role.kubernetes.io/control-plane-
kubectl label node k8s-control-plane-02 node-role.kubernetes.io/control-plane-
kubectl label node k8s-control-plane-03 node-role.kubernetes.io/control-plane-

kubectl get no
