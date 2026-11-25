# Relatório de Melhorias e Otimizações de Infraestrutura: Docker Swarm

## 1. Mapeamento da Infraestrutura e Cargas de Trabalho no Docker Swarm

A infraestrutura baseada em Docker Swarm é composta por um cluster de seis nós virtuais divididos estrategicamente entre gerenciadores de controle e executores de carga: três nós Manager (`docker-swarm-01`, `docker-swarm-02` e `docker-swarm-03`, sendo o nó 03 o Leader ativo do cluster) e três nós Worker (`docker-worker-01`, `docker-worker-02` e `docker-worker-03`). 

A plataforma abriga as principais ferramentas da esteira de integração e entrega contínua (CI/CD) e gerenciamento de infraestrutura da organização. As Stacks e Serviços distribuídos no cluster englobam:
* **`sonarqube-stack`**: Instância do SonarQube LTS Community Edition alocada no nó `docker-swarm-01`.
* **`jenkins-stack`**: Servidor de automação Jenkins LTS alocado no nó `docker-swarm-02`.
* **`semaphore`**: Interface de automação Ansible Semaphore UI executada no nó `docker-swarm-03`, conectada ao seu banco de dados PostgreSQL 14 (`semaphore-db`) hospedado no nó de trabalho `docker-worker-02`.
* **`traefik`**: Ingress/Reverse Proxy Traefik v2.11 executado como serviço global nos nós Manager, gerenciando o roteamento HTTP/HTTPS.
* **`portainer`**: Interface Portainer CE com agentes (`portainer-agent`) em modo global ativos em todos os seis nós do cluster.

---

## 2. Diagnóstico do Estado Atual e Pontos de Atenção (ANTES)

A medição de desempenho realizada no nó principal via `docker stats --no-stream` e `docker service ps` identificou pontos de atenção operacional que impactam a estabilidade e a segurança do cluster.

A tabela a seguir resume a alocação atual de recursos e a localização física das principais cargas de trabalho:

| Serviço / Stack | Imagem Container | Nó Alocado no Swarm | Consumo RAM Atual | Consumo CPU / PIDs | Estado Operacional / Alerta Diagnóstico |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `sonarqube` | `sonarqube:lts-community` | `docker-swarm-01` | 1.453 GiB (18.75%) | 1.92% CPU / 191 PIDs | Uso de banco H2 embutido (apenas para testes) |
| `jenkins` | `jenkins/jenkins:latest` | `docker-swarm-02` | 732 MiB | 2.60% CPU / Java VM | Sem limite superior de memória configurado |
| `semaphore-db` | `postgres:14-alpine` | `docker-worker-02` | ~150 MiB | 0.50% CPU | Banco relacional sem reserva no `docker-stack.yml` |
| `semaphore` | `semaphoreui/semaphore:v2.19.17` | `docker-swarm-03` | ~45 MiB | 0.10% CPU | Executando em nó Manager do Swarm |
| `traefik` | `traefik:v2.11` | `docker-swarm-01..03` | 22.98 MiB | 0.09% CPU / 9 PIDs | Modo global em nós Manager |
| `portainer-agent` | `portainer/agent:2.45.3` | Todos os 6 Nós | 26.64 MiB (por nó) | 0.42% CPU / 6 PIDs | Registros de tarefas com falhas prévias de startup |

### 2.1 Vulnerabilidades Críticas Identificadas
1. **SonarQube em Banco H2 Interno**: Os logs do serviço `sonarqube-stack_sonarqube` registraram o aviso explícito `H2 database should be used for evaluation purpose only`. O banco de dados embutido H2 não possui suporte para alta disponibilidade nem persistência segura em produção, correndo risco de corrupção de dados em caso de reinicialização do container.
2. **Execução de Cargas Pesadas em Nós Manager**: Ferramentas intensivas em memória e processamento (como SonarQube e Jenkins) estão rodando diretamente em `docker-swarm-01` e `docker-swarm-02`. Essa alocação concorre por recursos com o mecanismo de consenso Raft e a API do Docker Swarm.
3. **Ausência de Reservas e Limites (`deploy.resources`)**: Os arquivos `docker-stack.yml` não declaram restrições de consumo. Quando um job de compilação no Jenkins ou uma análise estática no SonarQube é iniciado, o processo Java pode consumir toda a memória física da VM host, provocando o travamento do nó.

---

## 3. Plano de Otimização e Padronização de Stacks YAML

Para garantir que o cluster Docker Swarm opere de forma estável, segura e resiliente, propõe-se um plano de ação focado em quatro pilares técnicos.

### 3.1 Definição de Fronteiras de Recursos (`deploy.resources`)
Assim como foi realizado no Kubernetes, todos os serviços no Docker Swarm devem conter a seção `deploy.resources` especificando `reservations` (garantia mínima) e `limits` (teto máximo).

Abaixo apresenta-se o trecho YAML recomendado para atualização da stack do Jenkins e do SonarQube:

```yaml
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts
    ports:
      - "50000:50000"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        reservations:
          cpus: '0.50'
          memory: 1024M
        limits:
          cpus: '1.50'
          memory: 2048M

  sonarqube:
    image: sonarqube:lts-community
    environment:
      - SONAR_JDBC_URL=jdbc:postgresql://sonar-db:5432/sonar
      - SONAR_JDBC_USERNAME=sonar
      - SONAR_JDBC_PASSWORD=sonar_secure_pass
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        reservations:
          cpus: '1.00'
          memory: 2048M
        limits:
          cpus: '2.00'
          memory: 3584M
```

### 3.2 Isolamento de Cargas e Restrições de Posicionamento (`placement.constraints`)
Para proteger o plano de controle do Swarm, os nós Manager (`docker-swarm-01`, `02` e `03`) devem ser dedicados exclusivamente ao gerenciamento do cluster e ao roteamento Ingress do Traefik.
* **Migração dos Workloads**: Adicionar a restrição `node.role == worker` nas Stacks do Jenkins, SonarQube e Semaphore UI para mover seus containers para os nós `docker-worker-01`, `02` e `03`.
* **Fixação de Bancos de Dados**: Manter bancos de dados relacionais vinculados a nós específicos via `node.hostname == docker-worker-02` para garantir alinhamento com os volumes persistentes locais ou compartilhados por NFS.

### 3.3 Persistência e Migração de Banco de Dados do SonarQube
Substituir a instância H2 do SonarQube por um banco de dados PostgreSQL 15 dedicado:
* **Criação da Stack de Banco**: Adicionar um serviço `sonar-db` utilizando a imagem `postgres:15-alpine` com volume persistente montado em `/var/lib/postgresql/data`.
* **Ajuste de Parâmetros do Kernel**: Garantir que o valor de `sysctl vm.max_map_count` esteja configurado como `1048576` em todos os nós executores do SonarQube (conforme validado na auditoria do ambiente), atendendo aos requisitos do mecanismo Elasticsearch interno do SonarQube.

### 3.4 Alta Disponibilidade, Proxy Reverso Traefik e Governança CI/CD
* **Monitoramento de Saúde (`healthcheck`)**: Incluir blocos de `healthcheck` nos serviços do Swarm para que tarefas com falhas (como as detectadas anteriormente no `portainer-agent`) sejam reiniciadas e substituídas automaticamente pelo Swarm Manager.
* **Isolamento de Pipelines no Jenkins**: Configurar os builds do Jenkins para utilizarem agentes dinâmicos em containers Docker em vez de rodar as compilações no próprio container principal do Jenkins Controller, eliminando o risco de estouro de disco e RAM na VM do master.
