# Relatório de Melhorias e Otimizações de Infraestrutura: Kubernetes (k8s)

## 1. Mapeamento da Infraestrutura e Diagnóstico Inicial (ANTES)

A infraestrutura analisada consiste em um cluster Kubernetes de alta disponibilidade composto por 6 nós virtuais executados sob a plataforma de virtualização Proxmox:
* **Plano de Controle (Control Plane)**: `k8s-control-plane-01`, `k8s-control-plane-02` e `k8s-control-plane-03`.
* **Nós de Execução (Workers)**: `k8s-worker-01`, `k8s-worker-02` e `k8s-worker-03`.

### 1.1 Medição Inicial de Recursos dos Nós (`kubectl top nodes`)
No estado inicial do ambiente, a distribuição de consumo de CPU e memória RAM apresentava-se desequilibrada, sobrecarregando o nó principal do Control Plane e gerando instabilidade na API do Kubernetes:

| Nó (Virtual Machine) | Função no Cluster | Consumo CPU (m) | Consumo CPU (%) | Consumo RAM (MiB) | Consumo RAM (%) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `k8s-control-plane-01` | Control Plane | 499m | 24% | 1309 MiB | 34% |
| `k8s-control-plane-02` | Control Plane | 434m | 21% | 1065 MiB | 27% |
| `k8s-control-plane-03` | Control Plane | 456m | 22% | 1231 MiB | 32% |
| `k8s-worker-01` | Worker Node | 246m | 12% | 1128 MiB | 29% |
| `k8s-worker-02` | Worker Node | 299m | 14% | 716 MiB | 18% |
| `k8s-worker-03` | Worker Node | 307m | 15% | 847 MiB | 22% |

### 1.2 Medição Inicial por Pod (`kubectl top pods -A`)
A medição dos Pods em execução destacou os seguintes serviços como principais consumidores de recursos:
* `kube-apiserver` (`k8s-control-plane-01`): 363m CPU | 564 MiB RAM.
* `argocd-application-controller`: 208m CPU | 116 MiB RAM.
* `zabbix-web`: 132m CPU | 117 MiB RAM.
* `zabbix-db`: 94m CPU | 368 MiB RAM.
* `zabbix-server`: 22m CPU | 57 MiB RAM.
* `zabbix-agent`: 4m CPU | 8 MiB RAM.

### 1.3 Causa Raiz do Gargalo Tecnológico
1. **Ausência de `requests` e `limits`**: A inspeção via `kubectl describe nodes | grep -A 8 "Allocated resources"` revelou que a coluna `Limits` registrava `0 (0%)` para todos os nós. 
2. **Falha de Agendamento do `kube-scheduler`**: Sem a definição de `requests`, o agendador do Kubernetes tratava as aplicações como tendo peso insignificante, concentrando Pods pesados no mesmo nó sem balanceamento prévio.
3. **Instabilidade do Control Plane**: Durante picos de processamento, a falta de limites fazia com que a VM do Control Plane ficasse sem recursos para responder à API, resultando em erros operacionais como `Unable to connect to the server: net/http: TLS handshake timeout`.
4. **Incompatibilidade no Zabbix Agent 2**: O container do `zabbix-agent2` registrava falhas de inicialização (`ERROR: Cannot validate configuration: failed to validate "ServerActive" parameter: failed to validate host: "0.0.0.0/0"`), decorrente da utilização da variável `ZBX_SERVER_HOST` com máscara CIDR para checagens ativas.

---

## 2. Ações Corretivas e Implementação Helm

Para corrigir os problemas identificados, foram implementadas as seguintes alterações no arquivo de manifesto Helm `templates/zabbix.yaml`:

### 2.1 Correção do Zabbix Agent 2
* Ajustou-se a variável de ambiente `ZBX_SERVER_HOST` para apontar diretamente ao nome de serviço DNS `zabbix-server`.
* Alinhou-se a interface no Zabbix Web para direcionar o tráfego de monitoramento passivo para o Service `zabbix-agent` na porta `10050`.

### 2.2 Inclusão do Bloco de Recursos (`requests` e `limits`)
Foi introduzida a governança de recursos computacionais para todos os contêineres da stack do Zabbix no `templates/zabbix.yaml`:

```yaml
# 1. ZABBIX DATABASE (MariaDB/MySQL)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zabbix-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zabbix-db
  template:
    metadata:
      labels:
        app: zabbix-db
    spec:
      containers:
        - name: zabbix-db
          image: {{ .Values.zabbixDb.image }}
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"

---
# 2. ZABBIX SERVER
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zabbix-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zabbix-server
  template:
    metadata:
      labels:
        app: zabbix-server
    spec:
      containers:
        - name: zabbix-server
          image: {{ .Values.zabbixServer.image }}
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"

---
# 3. ZABBIX WEB INTERFACE
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zabbix-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zabbix-web
  template:
    metadata:
      labels:
        app: zabbix-web
    spec:
      containers:
        - name: zabbix-web
          image: {{ .Values.zabbixWeb.image }}
          resources:
            requests:
              cpu: "150m"
              memory: "256Mi"
            limits:
              cpu: "300m"
              memory: "512Mi"

---
# 4. ZABBIX AGENT 2
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zabbix-agent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zabbix-agent
  template:
    metadata:
      labels:
        app: zabbix-agent
    spec:
      containers:
        - name: zabbix-agent
          image: {{ .Values.zabbixAgent.image }}
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
          env:
            - name: ZBX_SERVER_HOST
              value: "zabbix-server"
            - name: ZBX_HOSTNAME
              value: "Zabbix server"
          ports:
            - containerPort: {{ .Values.zabbixAgent.port }}
```

---

## 3. Análise Comparativa de Resultados (DEPOIS)

Após o deploy das alterações e o reinício controlado dos pods via `kubectl rollout restart deployment -n zabbix-helm --all`, coletou-se a nova baseline de métricas.

### 3.1 Comparativo por Nó (`kubectl top nodes`)

| Nó | CPU Antes | CPU Depois | Δ CPU (%) | RAM Antes | RAM Depois | Δ RAM (Absoluta) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `k8s-worker-01` | 246m (12%) | 206m (10%) | -2% | 1128 MiB (29%) | 979 MiB (25%) | **-149 MiB** |
| `k8s-worker-02` | 299m (14%) | 204m (10%) | -4% | 716 MiB (18%) | 646 MiB (16%) | **-70 MiB** |
| `k8s-worker-03` | 307m (15%) | 226m (11%) | -4% | 847 MiB (22%) | 890 MiB (23%) | +43 MiB (Estabilizado) |
| `k8s-control-plane-01` | 499m (24%) | 415m (20%) | **-4%** | 1309 MiB (34%) | 1303 MiB (34%) | -6 MiB |

### 3.2 Comparativo dos Pods do Zabbix (`kubectl top pods -A`)

| Pod / Serviço | CPU Antes | CPU Depois | Redução CPU | RAM Antes | RAM Depois | Redução RAM |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `zabbix-web` | 132m | 27m | **-79.5%** | 117 MiB | 61 MiB | **-47.8%** |
| `zabbix-db` | 94m | 29m | **-69.1%** | 368 MiB | 199 MiB | **-45.9% (-169 MiB)** |

### 3.3 Status da Alocação de Recursos
A verificação final confirmou que a seção `Allocated resources` agora reflete a reserva explícita dos contêineres, impedindo estouros de memória e permitindo que o `kube-scheduler` distribua novas cargas de trabalho de forma homogênea.

---

## 4. Recomendações Arquiteturais Futuras

1. **Governança por Namespaces**: Implementar objetos `ResourceQuota` e `LimitRange` nos namespaces (`zabbix-helm`, `jenkins`, `dev`) para impor limites padrão a qualquer Pod criado sem especificação explícita.
2. **Anti-Afinidade de Pods (`podAntiAffinity`)**: Para serviços replicados, adicionar regras de anti-afinidade no manifesto para proibir que réplicas do mesmo serviço sejam agendadas na mesma VM worker.
3. **Escalamento Horizontal (HPA)**: Configurar o `HorizontalPodAutoscaler` com base no consumo de CPU/RAM para aplicações sem estado (*stateless*), utilizando como gatilho 70% de utilização do `request`.
