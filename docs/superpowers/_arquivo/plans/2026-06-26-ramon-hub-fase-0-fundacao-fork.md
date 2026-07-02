# Ramon Hub — Fase 0: Fundação do Fork — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o clone raso do Chatwoot v4.15.1 em um **fork rebaseável** que builda numa imagem própria (GHCR via GitHub Actions) e roda na VPS no lugar da imagem stock — **idêntico ao upstream**, com os dados atuais intactos.

**Architecture:** O clone vira um fork de verdade (remote `upstream` = chatwoot/chatwoot, branch de trabalho `ramon`). Um workflow do GitHub Actions builda `docker/Dockerfile` e publica em `ghcr.io/<owner>/ramon-hub`. A VPS troca `chatwoot/chatwoot:latest` pela nossa imagem fixada `v4.15.1-ramon` e apenas dá `docker pull` — sem build na VPS. Como a fonte é a mesma v4.15.1, o schema do Postgres `chatwoot_production` não muda.

**Tech Stack:** Git, GitHub Actions, docker/build-push-action, GHCR, Docker Compose, Chatwoot 4.15.1 (Rails 7.1 / Ruby 3.4.4 / Vue 3 / Vite).

## Global Constraints

- **Base fixa:** Chatwoot **v4.15.1** (commit `97bb8ec`). Nunca subir a base sem uma tarefa deliberada de rebase.
- **Disciplina de fork:** arquivos NOVOS em namespace `ramon/`; editar só **pontos de registro** documentados; **nunca tocar `enterprise/`**.
- **Aprovação (banca):** Claude redige/propõe; **commits, push e deploy são executados/autorizados pelo Eduardo**. Passos marcados **[Eduardo]** exigem o ok explícito dele.
- **Registry:** `ghcr.io/<owner>/ramon-hub` (`<owner>` = login do dono do repo, minúsculo — o workflow resolve sozinho via `github.repository_owner`).
- **Repo local:** `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub` (no Git Bash: `/c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub`).
- **VPS:** `root@185.194.216.67`, stack em `/opt/intranet-ramon/docker-compose.yml`, Postgres `chatwoot_production` **preservado**.

---

### Task 0.1: Tornar o clone um fork rebaseável (git local)

**Files:**
- Modify: configuração git do repo `ramon-hub` (sem arquivos versionados alterados)

**Interfaces:**
- Consumes: o clone raso atual (`origin` = chatwoot/chatwoot, detached HEAD em v4.15.1).
- Produces: remote `upstream` = chatwoot/chatwoot; branch de trabalho **`ramon`** com histórico completo; tags upstream disponíveis localmente para rebase futuro.

- [ ] **Step 1: Renomear o remote e abrir o fetch para todas as refs**

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub
git remote rename origin upstream
git remote set-branches upstream '*'
```

- [ ] **Step 2: Baixar o histórico completo e as tags**

```bash
git fetch upstream --unshallow
git fetch upstream --tags
```

- [ ] **Step 3: Criar a branch de trabalho `ramon`**

```bash
git switch -c ramon
```

- [ ] **Step 4: Verificar o estado do fork**

```bash
git rev-parse --abbrev-ref HEAD     # esperado: ramon
git log --oneline -1                # esperado: 97bb8ec Merge branch 'release/4.15.1'
git tag --list | grep -c .          # esperado: > 1 (várias tags upstream)
git rev-list --count HEAD           # esperado: > 1000 (histórico real, não raso)
git rev-parse --is-shallow-repository   # esperado: false
```
Expected: branch `ramon`, histórico profundo, tags presentes.

*(Sem commit — nada versionado mudou.)*

---

### Task 0.2: Documentos de disciplina do fork

**Files:**
- Create: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: branch `ramon` (Task 0.1).
- Produces: o documento vivo que lista os arquivos do core editados — consultado a cada rebase.

- [ ] **Step 1: Criar `docs/FORK-PONTOS-DE-REGISTRO.md`**

```markdown
# Fork Ramon Hub — Pontos de registro tocados no core

> Toda edição em arquivo que **já existe no Chatwoot upstream** entra AQUI.
> Antes de cada rebase numa nova release, conferir esta lista é a checagem rápida.
> Regra de ouro: **adicionar (namespace `ramon/`), quase nunca editar.** Nunca tocar `enterprise/`.

## Base do fork
- Upstream: `chatwoot/chatwoot`
- Versão fixada: **v4.15.1** (commit `97bb8ec`)
- Branch de trabalho: `ramon`
- Imagem publicada: `ghcr.io/<owner>/ramon-hub:v4.15.1-ramon`

## Arquivos do core editados (manter mínimo)
| Arquivo | Linhas/trecho | Motivo | Fase |
|---|---|---|---|
| _(nenhum ainda)_ | | | |

## Arquivos NOVOS (namespace `ramon/` — não conflitam no rebase)
| Arquivo | Responsabilidade | Fase |
|---|---|---|
| `.github/workflows/ramon-publish.yml` | build + publish da imagem do fork no GHCR | 0 |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | esta lista | 0 |

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
```

- [ ] **Step 2: Commit [Eduardo]**

```bash
git add docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "docs(ramon): adiciona registro de pontos de fork"
```

- [ ] **Step 3: Verificar**

```bash
git log --oneline -1    # esperado: docs(ramon): adiciona registro de pontos de fork
git status              # esperado: working tree clean
```

---

### Task 0.3: Workflow de build e publish no GHCR

**Files:**
- Create: `.github/workflows/ramon-publish.yml`

**Interfaces:**
- Consumes: branch `ramon`, `docker/Dockerfile`.
- Produces: imagem `ghcr.io/<owner>/ramon-hub` com as tags `ramon` (móvel), `v4.15.1-ramon` (fixa) e `sha-<short>` (imutável). A VPS (Task 0.5) consome a tag fixa.

- [ ] **Step 1: Criar `.github/workflows/ramon-publish.yml`**

```yaml
name: Publica imagem do fork (GHCR)

on:
  push:
    branches: [ramon]
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login no GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Tags da imagem
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/ramon-hub
          tags: |
            type=raw,value=ramon
            type=raw,value=v4.15.1-ramon
            type=sha,prefix=sha-

      - name: Setup Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build e push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/Dockerfile
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            RAILS_ENV=production
```

- [ ] **Step 2: Registrar o arquivo novo no FORK-PONTOS (já listado) e commit [Eduardo]**

```bash
git add .github/workflows/ramon-publish.yml
git commit -m "ci(ramon): workflow de build/publish da imagem no GHCR"
```

- [ ] **Step 3: Verificar a sintaxe do YAML localmente**

Run:
```bash
git show HEAD:.github/workflows/ramon-publish.yml | head -5
```
Expected: imprime o cabeçalho `name: Publica imagem do fork (GHCR)`. (A validação real do workflow acontece na Task 0.4, ao rodar no GitHub.)

---

### Task 0.4: Repo privado no GitHub + primeiro push (dispara o build) [Eduardo]

**Files:**
- nenhum (operação de remote)

**Interfaces:**
- Consumes: branch `ramon` com os commits 0.2/0.3.
- Produces: repo privado `ramon-hub` no GitHub (`origin`); imagem publicada no GHCR.

- [ ] **Step 1: Confirmar login do gh e descobrir o owner**

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub
gh auth status
gh api user -q .login        # anote este valor = <owner>
```
Expected: autenticado; imprime o handle do GitHub.

- [ ] **Step 2: Criar o repo privado e apontar origin**

```bash
gh repo create ramon-hub --private --source=. --remote=origin
```
Expected: cria `https://github.com/<owner>/ramon-hub` (privado) e adiciona o remote `origin`. *(Só a branch `ramon` será enviada — as tags do upstream ficam locais, para rebase.)*

- [ ] **Step 3: Push da branch `ramon`**

```bash
git push -u origin ramon
```
Expected: push aceito; o evento `push` dispara o workflow.

- [ ] **Step 4: Verificar o build no Actions**

```bash
gh run list --workflow=ramon-publish.yml --limit 1
gh run watch        # acompanha até concluir
```
Expected: run **success** (build do Chatwoot leva ~10–20 min na primeira vez).

- [ ] **Step 5: Verificar a imagem no GHCR**

```bash
gh api "users/<owner>/packages/container/ramon-hub/versions" -q '.[0].metadata.container.tags'
```
Expected: lista incluindo `ramon`, `v4.15.1-ramon` e uma tag `sha-...`.

---

### Task 0.5: VPS — trocar a imagem stock pela do fork [Eduardo]

**Files:**
- Modify: `/opt/intranet-ramon/docker-compose.yml` (na VPS) — linha `image:` da âncora `x-chatwoot`

**Interfaces:**
- Consumes: imagem `ghcr.io/<owner>/ramon-hub:v4.15.1-ramon` (Task 0.4).
- Produces: `chatwoot-web`/`chatwoot-worker` rodando a nossa imagem; dados intactos.

- [ ] **Step 1: Backup do compose e login no GHCR (na VPS)**

```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67
cd /opt/intranet-ramon
cp docker-compose.yml docker-compose.yml.bak
# PAT com escopo read:packages (criar em github.com/settings/tokens):
echo "$GHCR_PAT" | docker login ghcr.io -u <owner> --password-stdin
```
Expected: `Login Succeeded`.

- [ ] **Step 2: Trocar a imagem na âncora `x-chatwoot`**

Editar a linha (uma só — vale para web, worker e init):
```yaml
# de:
  image: chatwoot/chatwoot:latest   # imagem multi-arch (amd64+arm64), igual ao compose oficial
# para:
  image: ghcr.io/<owner>/ramon-hub:v4.15.1-ramon   # fork fixado em v4.15.1
```

- [ ] **Step 3: Puxar a imagem e subir só os serviços do Chatwoot**

```bash
docker compose pull chatwoot-web chatwoot-worker
docker compose up -d chatwoot-web chatwoot-worker
```
Expected: pull da nova imagem; containers recriados sem erro.

- [ ] **Step 4: Smoke test — versão, app e dados intactos**

```bash
docker exec intranet-ramon-chatwoot-web-1 sh -c 'cat /app/package.json | grep -m1 version'
# esperado: "version": "4.15.1"
docker exec intranet-ramon-chatwoot-web-1 cat /app/.git_sha
# esperado: 97bb8ecd...  (commit do nosso fork = v4.15.1)
curl -sI https://chat.ramonantonio.adv.br | head -1
# esperado: HTTP/2 200 (ou 302 para login)
```
E no navegador: logar em `chat.ramonantonio.adv.br`, confirmar que **conversas e contatos atuais aparecem** (mesmo Postgres) e que o contato de teste "Teste Lead" segue lá.

- [ ] **Step 5: Rollback documentado (só se quebrar)**

```bash
cd /opt/intranet-ramon
cp docker-compose.yml.bak docker-compose.yml
docker compose up -d chatwoot-web chatwoot-worker
```
Expected: volta para `chatwoot/chatwoot:latest` sem perda de dados.

- [ ] **Step 6: Registrar o resultado**

Anotar na sessão/memória: imagem do fork no ar, tag `v4.15.1-ramon`, smoke test ok. (Atualizar a tabela "core editados" do FORK-PONTOS se algo do core tiver sido tocado — nesta fase, nada foi.)

---

## Self-Review

**Spec coverage (Fase 0 do spec):**
- "remote upstream + branch `ramon`" → Task 0.1 ✓
- "namespace `ramon/` + lista de pontos de registro" → Task 0.2 ✓
- "build próprio fixado em v4.15.1 (substitui `:latest`)" → Tasks 0.3 + 0.5 ✓
- "subir o fork e validar dados intactos (mesmo Postgres)" → Task 0.5 Step 4 ✓
- "risco do `:latest` migrar sozinho → fixar a tag" → Task 0.5 Step 2 ✓

**Resultado da fase:** a casa de Conversas roda a **nossa imagem** (idêntica ao 4.15.1), pronta para receber rebrand e o trilho na Fase 1 — com pipeline de build e caminho de rebase já estabelecidos.

---

*Próximo passo após executar a Fase 0: escrever o plano da **Fase 1 (rebrand + trilho)** contra os arquivos reais já dentro do fork (`Sidebar.vue`, `tailwind.config.js`/`theme/colors`, `installation_config.yml`, índice de rotas) — código exato, sem chute.*
