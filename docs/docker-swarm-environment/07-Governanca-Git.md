# 🛡️ Doc 7 — Governança Git

> **Autor:** Joel Fernandes  
> **Data:** 01/10/2026  
> **Objetivo:** Definir o padrão de higiene e governança Git para todos os repositórios do ambiente NVerse, prevenindo vazamento de segredos, commits inconsistentes e histórico poluído.  
> **Público:** Qualquer pessoa que for commitar neste ou nos demais repositórios do projeto.

---

## 📋 Sumário

1. [Por que Governança Git importa](#1-por-que-governança-git-importa)
2. [Checklist Pré-Push](#2-checklist-pré-push)
3. [.gitignore Recomendado](#3-gitignore-recomendado)
4. [Convenções de Commit](#4-convenções-de-commit)
5. [Fluxo Diário Recomendado](#5-fluxo-diário-recomendado)
6. [Recuperação de Erros Comuns](#6-recuperação-de-erros-comuns)
7. [Referências Cruzadas](#7-referências-cruzadas)

---

## 1. Por que Governança Git importa

Um repositório de infraestrutura (Terraform, Ansible, Docker, etc.) **não é um repositório qualquer**. Ele contém:

- 🔑 **Credenciais** (mesmo que indiretas)
- 🗺️ **Topologia** da sua rede (IPs, hostnames, portas)
- ⚙️ **Configurações** que, expostas, permitem ataques direcionados

Um único `git push` descuidado pode:
- ❌ Vazar senhas, tokens e chaves
- ❌ Expor `tfstate` com IDs de recursos
- ❌ Publicar arquivos `acme.json` com chaves TLS
- ❌ Enviar tokens do Docker Swarm (`SWMTKN-*`)
- ❌ Deixar arquivos gigantes que **nunca mais saem** do histórico

> 🥇 **Regra de ouro:** trate todo repositório de infra como se fosse **público**. Mesmo que seja privado hoje, pode virar público amanhã.

---

## 2. Checklist Pré-Push

> 🚨 **Nunca** dê `git push` sem rodar esta sequência. São 30 segundos que evitam dias de dor de cabeça.

```bash
# 1. O que vai subir?
git status

# 2. Revisar staged linha a linha
git diff --cached

# 3. Quais commits vão?
git log origin/main..HEAD --oneline

# 4. Caçar segredos rastreados
git ls-files | grep -Ei "(secret|password|token|\.pem|\.key|\.crt|tfstate|tfplan|\.env|acme\.json|vault_pass)"
```

**Regra de decisão:**

| Resultado do passo 4 | Ação |
|----------------------|------|
| Vazio (nada retornado) | ✅ Siga para o push |
| Qualquer arquivo listado | 🛑 **PARE** e resolva antes |

Se o passo 4 retornar algo:

```bash
# Remover do rastreamento SEM apagar do disco
git rm --cached <arquivo>

# Adicionar ao .gitignore
echo "<padrão>" >> .gitignore

# Refazer o commit (se ainda não foi pushado)
git commit --amend --no-edit
```

Se **já foi pushado** com segredo:

```bash
# 1. Rotacione TODAS as credenciais expostas (senhas, tokens, chaves)
# 2. Considere limpar o histórico (git filter-repo / BFG)
# 3. Force-push coordenado com o time
```

---

## 3. .gitignore Recomendado

> 💡 Copie este bloco para a **raiz** de cada repositório. Ajuste conforme a stack específica.

```gitignore
# =====================================================
# Terraform
# =====================================================
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfstate.backup
*.tfplan
tfplan
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# =====================================================
# Ansible
# =====================================================
*.retry
.vault_pass
*.vault_pass
inventory/*.ini.bak

# =====================================================
# Docker / Swarm
# =====================================================
acme.json
*.pem
*.key
*.crt
*.csr

# =====================================================
# Segredos e credenciais
# =====================================================
.env
.env.*
!.env.example
secrets.tfvars
secrets.tfvars.json
*password*
*token*
*secret*

# =====================================================
# Sistema operacional
# =====================================================
.DS_Store
Thumbs.db
*~

# =====================================================
# Editores / IDEs
# =====================================================
.vscode/
.idea/
*.swp
*.swo
*.sublime-*

# =====================================================
# Logs e temporários
# =====================================================
*.log
*.tmp
*.bak

# =====================================================
# Python (se aplicável)
# =====================================================
__pycache__/
*.py[cod]
.venv/
venv/

# =====================================================
# Node (se aplicável)
# =====================================================
node_modules/
npm-debug.log*
yarn-error.log*
```

### 3.1 Checklist do `.gitignore` maduro

Antes de confiar no `.gitignore`, valide:

```bash
# Testa se um arquivo seria ignorado
git check-ignore -v caminho/do/arquivo

# Lista tudo que está rastreado e deveria estar ignorado
git ls-files | grep -Ei "(secret|password|token|\.pem|\.key|\.crt|tfstate|tfplan|\.env|acme\.json)" || echo "✅ Limpo"
```

---

## 4. Convenções de Commit

> 🎯 Usamos **Conventional Commits** — padrão da indústria, legível por humanos e por ferramentas.

### 4.1 Formato

```
<tipo>(<escopo>): <descrição curta>

[corpo opcional]

[rodapé opcional]
```

### 4.2 Tipos

| Tipo | Quando usar |
|------|-------------|
| `feat` | Nova funcionalidade / novo recurso |
| `fix` | Correção de bug |
| `docs` | Apenas documentação |
| `style` | Formatação (sem mudança de lógica) |
| `refactor` | Refatoração (sem mudança de comportamento) |
| `chore` | Tarefas de manutenção (build, deps, configs) |
| `test` | Adição/ajuste de testes |
| `ci` | Mudanças em CI/CD |

### 4.3 Exemplos do nosso ambiente

```bash
# Adicionar nova stack
git commit -m "feat(stacks): adiciona stack do Traefik v3"

# Corrigir config de rede
git commit -m "fix(swarm): corrige porta 7946/udp no UFW"

# Documentar
git commit -m "docs(swarm): adiciona roteiro de reprodução do ambiente"

# Manutenção
git commit -m "chore(gitignore): adiciona padrões para acme.json e tfstate"

# Refatorar playbook
git commit -m "refactor(ansible): separa tarefas base e docker"
```

### 4.4 Boas práticas

- ✅ **Verbo no imperativo** ("adiciona", "corrige", "remove") — em português ou inglês, escolha um e mantenha
- ✅ **Descrição curta** na primeira linha (até ~72 caracteres)
- ✅ **Corpo** para explicar o "porquê", não o "o quê"
- ❌ Não use "update", "fix", "wip" sozinho — seja específico
- ❌ Não misture assuntos em um commit (um commit = uma mudança lógica)

---

## 5. Fluxo Diário Recomendado

### 5.1 Início de sessão

```bash
cd <repositório>
git status                    # onde estou?
git fetch origin              # tem novidade no remoto?
git log HEAD..origin/main --oneline   # quantos commits atrás?
```

### 5.2 Se estiver atrás do remoto

```bash
git pull --ff-only origin main
# ou, se houver divergência:
git pull --rebase origin main
```

### 5.3 Trabalhar e commitar

```bash
# ... edições ...
git status                    # ver o que mudou
git add <arquivo específico>  # ✅ PREFERÍVEL
# git add .                   # ⚠️ só com .gitignore maduro
git diff --cached             # revisar staged
git commit -m "tipo(escopo): descrição"
```

### 5.4 Antes de publicar

```bash
# Checklist pré-push (Seção 2)
git status
git diff --cached
git log origin/main..HEAD --oneline
git ls-files | grep -Ei "(secret|password|token|\.pem|\.key|\.crt|tfstate|tfplan|\.env|acme\.json)" || echo "✅ Limpo"

# Só então:
git push origin main
```

---

## 6. Recuperação de Erros Comuns

### 6.1 Commitei um arquivo que não devia

```bash
# Remover do rastreamento, mantendo no disco
git rm --cached caminho/arquivo

# Adicionar ao .gitignore
echo "caminho/arquivo" >> .gitignore

# Refazer o commit
git commit --amend --no-edit
```

### 6.2 Preciso desfazer o último commit (mantendo as mudanças)

```bash
# Volta o commit, mantém tudo staged
git reset --soft HEAD~1

# Volta o commit, mantém tudo no working tree (não staged)
git reset HEAD~1

# Volta o commit e DESCARTA as mudanças (⚠️ perigoso)
git reset --hard HEAD~1
```

### 6.3 Preciso guardar mudanças temporariamente

```bash
# Guardar
git stash push -m "descrição" -- arquivo

# Ver o que está guardado
git stash list
git stash show -p stash@{0}

# Recuperar
git stash pop

# Descartar (⚠️ irreversível)
git stash clear
```

### 6.4 Preciso descartar mudanças locais em um arquivo

```bash
# ⚠️ IRREVERSÍVEL — não vai para stash
git checkout -- arquivo
# ou (moderno):
git restore arquivo
```

> 💡 **Antes de descartar**, faça `cp arquivo arquivo.bak` ou `git stash`. `checkout --` não tem volta.

### 6.5 `git push` falhou porque estou atrás

```bash
git pull --rebase origin main
git push origin main
```

### 6.6 Commitei segredo e **já foi pushado**

> 🚨 **Isso é incidente de segurança.** Ordem de prioridade:

1. **Rotacione TODAS as credenciais expostas** (senhas, tokens, chaves SSH, certificados TLS)
2. Considere o segredo como **vazado para sempre** (mesmo deletando o commit, ele fica no histórico do GitHub por dias)
3. Se o repo é público, **ative alertas de secret scanning** no GitHub
4. Se necessário, limpe o histórico com [`git filter-repo`](https://github.com/newren/git-filter-repo) ou [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)
5. Force-push coordenado com todos que usam o repo (avise **antes**)

---

## 7. Referências Cruzadas

| Documento | Assunto |
|-----------|---------|
| **[01-Template-Proxmox-CloudInit.md](./01-Template-Proxmox-CloudInit.md)** | Templates Proxmox com cloud-init |
| **[02-Provisionamento-Terraform.md](./02-Provisionamento-Terraform.md)** | Provisionamento das VMs |
| **[03-Base-Ubuntu-Swarm.md](./03-Base-Ubuntu-Swarm.md)** | Preparação da VM (NTP, kernel, UFW, timestamp) |
| **[04-Docker-Swarm-Traefik-Portainer.md](./04-Docker-Swarm-Traefik-Portainer.md)** | Instalação do Docker + Swarm + stacks |
| **[05-Ansible-Docker-Swarm.md](./05-Ansible-Docker-Swarm.md)** | Playbooks Ansible |
| **[06-Portainer-via-Ansible.md](./06-Portainer-via-Ansible.md)** | Portainer + Traefik |
| **07-Governanca-Git.md** *(este documento)* | Checklist, `.gitignore`, convenções |
| **[08-PostgreSQL-Multi-Disco-Ansible-Vault.md](./08-PostgreSQL-Multi-Disco-Ansible-Vault.md)** | PostgreSQL multi-disco |
| **[09-MariaDB-Multi-Disco-Ansible-Vault.md](./09-MariaDB-Multi-Disco-Ansible-Vault.md)** | MariaDB multi-disco |
| **[10-NFS-Server-Ansible.md](./10-NFS-Server-Ansible.md)** | Servidor NFS para persistência |


---

## 🧠 Lições Aprendidas

1. **Confie, mas verifique**: `git status` mente até você rodar `git fetch`. Sempre.
2. **Nunca** commite sem rodar o **Checklist Pré-Push**.
3. **`git add .`** só é seguro com `.gitignore` maduro.
4. **`git rm --cached`** remove do Git, mantém no disco — o comando certo para "não quero isso versionado".
5. **`--amend`** só é seguro **antes** do push.
6. **Segredo pushado = segredo vazado**: rotacione, não apenas delete.
7. **Um commit = uma mudança lógica**: não misture assuntos.
8. **Conventional Commits** é o padrão — use desde o primeiro commit.

---

*Documento gerado em 01/10/2026 como parte do roteiro oficial de reprodução do ambiente NVerse.*
