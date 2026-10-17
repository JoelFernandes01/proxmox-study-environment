### ☸ Doc 5 — Bootstrap e Inicialização do Cluster via Kubeadm
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a instalação do container runtime (containerd), binários do Kubernetes v1.30, inicialização do Control Plane Principal e adição dos demais Control Planes e Workers ao cluster HA.  
**Pré-requisito:** VMs preparadas e VIP 10.0.39.50:6443 operacional.

---

#### 1. Instalação e Configuração do Containerd

Executado em todos os nós do Kubernetes:

```bash
sudo apt update && sudo apt install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
```
