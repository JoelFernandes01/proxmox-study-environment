Comandos de Verificação e Inicialização
1. Para obter a senha inicial do Jenkins diretamente pelos logs via terminal:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs jenkins-stack_jenkins 2>&1 | grep -A 2 'Please use the following password'"

2. Para verificar a gravação dos dados nos diretórios do servidor NFS (10.0.39.30):

ssh -i ~/.ssh/id_terraform connect@10.0.39.30 "ls -la /srv/nfs/jenkins /srv/nfs/sonarqube"

Dois Comandos para Acompanhar a Subida
1. Logs de Inicialização do Jenkins (para ver o progresso e a senha admin):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs jenkins-stack_jenkins --tail 30"

2. Status e Logs do SonarQube (para verificar o download e inicialização):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service ps sonarqube-stack_sonarqube && docker service logs sonarqube-stack_sonarqube --tail 30"

Dois Comandos para Validação Final de Rede e Proxy
Para testar a resposta do serviço e verificar o roteamento no Traefik, execute os dois comandos abaixo:
1. Testar o cabeçalho HTTP da Web API do SonarQube:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -I http://10.0.39.31:9000"

2. Confirmar a detecção do serviço nos logs do Traefik:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs traefik_traefik --tail 20"

Dois Comandos para Validação da Rede do Traefik e Jenkins
Para confirmar que os endpoints do Jenkins e do Traefik também estão respondendo com HTTP 200 OK antes de cadastrarmos o pipeline, execute os dois comandos abaixo:
1. Comando 1 (Validar a resposta HTTP do Traefik / Dashboard):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -I http://10.0.39.31:8080/ping"

1. Comando 2 (Validar a resposta HTTP do Jenkins):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -I http://10.0.39.31:50000"

Dois Comandos para Validação Final de todos os FQDNs
Para confirmar que o Traefik está respondendo 200 OK para o Jenkins e para o Portainer no nível do serviço Swarm, execute os dois comandos abaixo:
1. Verificar as labels no nível do serviço Swarm do Portainer:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service inspect portainer_portainer --format '{{json .Spec.Labels}}'"

2. Simular o roteamento FQDN do Jenkins sem porta:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -I -H 'Host: jenkins.nverse.local' http://10.0.39.31"


Dois Comandos para Teste e Validação
Execute os dois comandos abaixo no seu terminal:
1. Comando 1 (Verificar a renderização do título HTML do Jenkins via Traefik):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -L -H 'Host: jenkins.nverse.local' http://10.0.39.31 | grep -i '<title>'"

2. Comando 2 (Verificar os últimos eventos do Traefik no Swarm):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs traefik_traefik --tail 15"

Dois Comandos para Validação de Código HTTP via Traefik
Execute os dois comandos abaixo no seu terminal:
1. Comando 1 (Verificar o código HTTP retornado pelo Jenkins):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: jenkins.nverse.local' http://10.0.39.31"

2. Comando 2 (Verificar o código HTTP retornado pelo SonarQube):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: sonarqube.nverse.local' http://10.0.39.31"


Próximos 2 Comandos para Validação de Saúde dos Serviços
Para confirmarmos o endpoint de login do Jenkins e a API de saúde do SonarQube via Traefik, execute os dois comandos abaixo:
1. Comando 1 (Testar o acesso direto à rota /login do Jenkins):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: jenkins.nverse.local' http://10.0.39.31/login"

2. Comando 2 (Verificar o Health Check da API do SonarQube):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -H 'Host: sonarqube.nverse.local' http://10.0.39.31/api/system/health"


Dois Comandos para Validação Final do Status e Senha
Execute os dois comandos abaixo para obter o status público do SonarQube e recuperar a senha de instalação do Jenkins:
1. Consultar a API de status do SonarQube (endpoint público de versão/saúde):

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -H 'Host: sonarqube.nverse.local' http://10.0.39.31/api/system/status"

2. Resgatar a senha inicial do administrador do Jenkins via logs:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs jenkins_jenkins 2>&1 | grep -A 2 'Please use the following password'"

Dois Comandos de Diagnóstico para Inspecionar as Labels do SonarQube
Para garantirmos que a label da stack do SonarQube no Swarm está idêntica à do Portainer/Jenkins, execute estes dois comandos no seu terminal:
1. Verificar as labels oficiais registradas no serviço do SonarQube:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service inspect sonarqube_sonarqube --format '{{json .Spec.Labels}}' | jq"

2. Testar o acesso via FQDN simulando a requisição do navegador:

ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -sI -H 'Host: sonarqube.nverse.local' http://10.0.39.31"

6. Validação das Stacks de CI/CD (Jenkins e SonarQube)

# 6.1 Confirmar o estado e réplicas de todas as stacks no Swarm (1/1)
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service ls"

# 6.2 Resgatar a senha inicial de administrador do Jenkins
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "docker service logs jenkins_jenkins 2>&1 | grep -A 2 'Please use the following password'"

# 6.3 Validar o acesso HTTP à rota de login do Jenkins via Traefik (Retorno 200 OK)
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: jenkins.nverse.local' http://10.0.39.31/login"

# 6.4 Validar o status de saúde da API do SonarQube via Traefik (Retorno status UP)
ssh -i ~/.ssh/id_terraform connect@10.0.39.31 "curl -s -H 'Host: sonarqube.nverse.local' http://10.0.39.31/api/system/status"

# 6.5 Confirmar gravação e persistência de dados no Servidor NFS
ssh -i ~/.ssh/id_terraform connect@10.0.39.30 "ls -la /srv/nfs/jenkins /srv/nfs/sonarqube /srv/nfs/portainer"
