### 🚀 Doc 9 — Ecossistema DevOps e Operações de Dia 2 via Helm
**Autor:** Joel Fernandes  
**Data:** 17/10/2026  
**Objetivo:** Documentar a infraestrutura de ferramentas DevOps de Dia 2 implantadas sobre o cluster Kubernetes através do Helm v4, estruturadas em camadas funcionais.  
**Pré-requisito:** Cluster operacional com CNI Calico e StorageClass `nfs-client` ativas (**Docs 7 e 8**).

---

#### 📋 Sumário
1. [Ferramental da Estação do Administrador](#1-ferramental-da-estação-do-administrador)
2. [Mapeamento das Camadas do Ecossistema DevOps](#2-mapeamento-das-camadas-do-ecossistema-devops)
3. [Comandos de Implantação Helm](#3-comandos-de-implantação-helm)
4. [Validação e Ingresses](#4-validação-e-ingresses)

---

#### 1. Ferramental da Estação do Administrador
- **Helm v4**: Gerenciador de pacotes e Charts do Kubernetes.
- **K9s**: Terminal UI para gerenciamento em tempo real do cluster.
- **Kubectx / Kubens**: Troca rápida de contexto e namespace.

---

#### 2. Mapeamento das Camadas do Ecossistema DevOps

| Camada | Ferramenta / Serviço | Chart Repository / Namespace | Função Principal |
|---|---|---|---|
| **Camada 1** | Ingress NGINX / Traefik | `ingress-nginx` / `traefik` | Roteamento HTTP/HTTPS e Ingress Controller |
| **Camada 1** | MetalLB | `metallb` | Alocação de IPs virtuais LoadBalancer na LAN |
| **Camada 1** | Cert-Manager | `jetstack` | Emissão e renovação automática de certificados SSL |
| **Camada 2** | Harbor | `harbor` | Registry privado OCI para imagens Docker e Helm Charts |
| **Camada 2** | Gitea | `gitea` | Servidor Git privado leve e integrado |
| **Camada 2** | ArgoCD | `argo` | Entrega Contínua e GitOps |
| **Camada 3** | Jenkins | `jenkins` | Servidor de automação CI/CD |
| **Camada 3** | SonarQube | `sonarqube` | Análise estática de código e segurança |

---

#### 3. Comandos de Implantação Helm

```bash
# 1. Ingress NGINX
helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace -n ingress-nginx

# 2. ArgoCD (GitOps)
helm install argocd argo/argo-cd --create-namespace -n argocd

# 3. Harbor Registry
helm install harbor harbor/harbor --create-namespace -n harbor \
  --set persistence.persistentVolumeClaim.registry.storageClass=nfs-client
```

---

- **Próximo Passo**: **[10-Governanca-Git-DevOps.md](./10-Governanca-Git-DevOps.md)**.
