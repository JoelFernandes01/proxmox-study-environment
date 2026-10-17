### ⚖️ Doc 4 — Alta Disponibilidade com Keepalived e HAProxy
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a configuração da camada de Load Balancing e Alta Disponibilidade para o endpoint da API do Kubernetes (`10.0.39.50:6443` - `k8s-vip.nverse.local`), utilizando Keepalived para gestão do Virtual IP e HAProxy para balanceamento de carga entre os 3 Control Planes.  
**Pré-requisito:** VMs `k8s-haproxy-01` e `02` provisionadas e preparadas (**Docs 2 e 3**).

---

#### 📋 Sumário
1. [Arquitetura da Camada HA](#1-arquitetura-da-camada-ha)
2. [Habilitação do Non-Local IP Binding](#2-habilitação-do-non-local-ip-binding)
3. [Configuração do Keepalived](#3-configuração-do-keepalived)
4. [Configuração do HAProxy](#4-configuração-do-haproxy)
5. [Automação via Playbooks Ansible](#5-automação-via-playbooks-ansible)
6. [Validação e Teste de Failover](#6-validação-e-teste-de-failover)
7. [Troubleshooting & Referências Cruzadas](#7-troubleshooting--referências-cruzadas)

---

#### 1. Arquitetura da Camada HA

```
                    Virtual IP (VIP): 10.0.39.50:6443
                     FQDN: k8s-vip.nverse.local
                                 |
           +---------------------+---------------------+
           |                                           |
 [ k8s-haproxy-01 ]                         [ k8s-haproxy-02 ]
   (10.0.39.41)                                (10.0.39.42)
 Keepalived (MASTER - Priority 101)        Keepalived (BACKUP - Priority 100)
 HAProxy                                   HAProxy
           |                                           |
           +---------------------+---------------------+
                                 |
    +----------------------------+----------------------------+
    |                            |                            |
[ k8s-control-plane-01 ]   [ k8s-control-plane-02 ]   [ k8s-control-plane-03 ]
 (10.0.39.43:6443)           (10.0.39.44:6443)           (10.0.39.45:6443)
```

---

#### 2. Habilitação do Non-Local IP Binding
Permite que os serviços façam bind no VIP `10.0.39.50` mesmo quando a interface ainda não é a detentora do IP:

```bash
echo "net.ipv4.ip_nonlocal_bind = 1" | sudo tee -a /etc/sysctl.d/haproxy.conf
sudo sysctl --system
```

---

#### 3. Configuração do Keepalived

##### Master (`k8s-haproxy-01`) — `/etc/keepalived/keepalived.conf`
```conf
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass NverseK8sHAPass
    }

    virtual_ipaddress {
        10.0.39.50/24 dev eth0
    }

    track_script {
        check_haproxy
    }
}
```

##### Backup (`k8s-haproxy-02`) — `/etc/keepalived/keepalived.conf`
```conf
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass NverseK8sHAPass
    }

    virtual_ipaddress {
        10.0.39.50/24 dev eth0
    }

    track_script {
        check_haproxy
    }
}
```

---

#### 4. Configuração do HAProxy — `/etc/haproxy/haproxy.cfg`

Aplicado em **ambos** os nós de Load Balancer:

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend k8s-api-frontend
    bind 10.0.39.50:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 25 weight 100
    server k8s-control-plane-01 10.0.39.43:6443 check
    server k8s-control-plane-02 10.0.39.44:6443 check
    server k8s-control-plane-03 10.0.39.45:6443 check
```

---

#### 5. Automação via Playbooks Ansible

- `playbooks/keepalived/02-configura-keepalived.yml`
- `playbooks/loadbalancer/03-configura-haproxy.yml`

Ambos são executados sequencialmente na esteira principal `site.yml`.

---

#### 6. Validação e Teste de Failover

```bash
# 1. Validar VIP no Master (k8s-haproxy-01)
ssh connect@10.0.39.41 "ip addr show eth0 | grep 10.0.39.50"
# Esperado: inet 10.0.39.50/24 scope global secondary eth0

# 2. Teste de failover: parar Keepalived no Master
ssh connect@10.0.39.41 "sudo systemctl stop keepalived"

# 3. Validar migração automática do VIP para o Backup (k8s-haproxy-02)
ssh connect@10.0.39.42 "ip addr show eth0 | grep 10.0.39.50"
# Esperado: inet 10.0.39.50/24 retido no backup

# 4. Reiniciar Keepalived no Master
ssh connect@10.0.39.41 "sudo systemctl start keepalived"
```

---

- **Próximo Passo**: **[05-Kubernetes-Cluster-Kubeadm.md](./05-Kubernetes-Cluster-Kubeadm.md)**.
