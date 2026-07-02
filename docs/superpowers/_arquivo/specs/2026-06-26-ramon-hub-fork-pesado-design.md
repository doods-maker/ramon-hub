# Ramon Hub — Fork pesado do Chatwoot (app único: Conversas + Intranet)

> **Status:** rascunho de design, aguardando revisão do Eduardo.
> **Data:** 2026-06-26.
> **Regra de aprovação:** Claude redige; **Eduardo aprova, comita e deploya**. Nada
> aqui foi commitado nem implementado.
> **Alvo de UX/marca:** `intranet-ramon/design-ref/` (protótipo "Ramon Antonio Hub" +
> `design-ref/CLAUDE.md`). Tratar como fonte de verdade visual/funcional.
> **Supera:** `2026-06-24-chatwoot-casa-unica-design.md` (abordagem casca-leve+iframe).
> Aqui o Eduardo decidiu o **fork pesado em Vue/Rails** — um app nativo, não iframe.

## Objetivo

Construir **uma casa só**: um fork do **Chatwoot 4.15.1** onde o time alterna, por um
**trilho lateral**, entre **Conversas** (Chatwoot rebrandizado) e **Intranet** (Centro de
Comando, Funil, SDR, Jurídico, IA) — tudo nativo (Rails + Vue), mesma URL, **um login**,
**um banco**. A inteligência comercial hoje na intranet Next.js/Supabase (funil, scoring,
Kit do Closer, qualificação por IA) **migra para dentro do fork**, e o Supabase é
**aposentado de forma faseada**.

## Decisões travadas (2026-06-26)

- **Estratégia:** fork pesado — Intranet renasce **nativa** em Vue/Rails dentro do
  Chatwoot. O Next.js atual vira referência/legado.
- **Base do fork:** Chatwoot **v4.15.1** (a mesma imagem no ar; digest de 2026-06-17).
- **Dados/cérebro:** `Lead` (e scoring, documentos) viram **tabelas nativas Rails** no
  Postgres que **já roda na VPS** (`chatwoot_production`, `pgvector/pg16`). **Sem novo
  banco pra hospedar.** Vantagem do fork pesado: `Lead`↔`Contact`↔`Conversation` por
  **JOIN no mesmo banco**, sem sync entre sistemas.
- **Migração faseada:** cria o `Lead` nativo já pra estrutura/kanban; porta
  scoring/Kit/IA do Supabase **módulo a módulo**; **desliga o Supabase ao final.**
- **Login:** consolida no **Devise nativo do Chatwoot** (some o Supabase Auth).
- **Padrão de store:** **Vuex** (`store/modules/`), que é o dominante no 4.15.1 e onde
  vivem `conversations`/`contacts`/`labels`. (Pinia existe em piloto — não usar pro
  nosso código por ora.)
- **WhatsApp:** segue o canal nativo do Chatwoot (Cloud API). Fora de escopo: múltiplas
  instâncias / HTTP API não-oficial.

## Arquitetura final (alvo)

```
VPS (185.194.216.67, 8GB) — um app, um banco, um login
┌─────────────────────────────────────────────────────────────┐
│ ramon-hub  (fork Chatwoot 4.15.1: Rails + Vue 3/Vite)         │
│   Trilho: [Conversas] [Intranet] + Externos (nova aba)        │
│   Conversas = Chatwoot rebrandizado (atendimento intacto)     │
│   Intranet  = Centro de Comando · Funil · SDR · Jurídico · IA │
│        │                                                      │
│        ▼                                                      │
│ postgres  chatwoot_production  (pgvector/pg16)                │
│   nativo:  contacts · conversations · inboxes · labels        │
│   novo:    leads · lead_scores · lead_documents               │
│ redis · (worker Sidekiq) · caddy (TLS)                        │
└─────────────────────────────────────────────────────────────┘
   Supabase + container Next.js  →  aposentados ao final da migração
```

## Inspeção real do 4.15.1 (caminhos confirmados)

Clone em `comercial/projetos/ramon-hub/` (shallow, tag v4.15.1).

| Área | Caminho real | Nota |
|---|---|---|
| Stack | Vue 3.5.12 · Vite 6.4 · Rails ~7.1 · Ruby 3.4.4 · Tailwind 3.4 | — |
| Store | `app/javascript/dashboard/store/modules/` (Vuex 4.1, dominante) | Pinia 3.0 em piloto em `stores/` |
| Trilho/sidebar | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (+ `SidebarGroup/Leaf/SubGroup`) | **não** existe `Primary.vue`; é composição modular |
| Índice de rotas | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | cada seção tem seu `*.routes.js` |
| Painel da conversa | `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` | subcomp.: `contact/`, `customAttributes/CustomAttributes.vue` |
| Custom attributes | `conversation/customAttributes/CustomAttributes.vue` | lê `currentChat.custom_attributes` |
| Branding | `config/installation_config.yml` | `INSTALLATION_NAME`, `BRAND_NAME`, `LOGO`, `LOGO_DARK`, `BRAND_URL` |
| Tema | `tailwind.config.js` → `theme/colors` + SCSS `assets/scss/_next-colors.scss` | rebrand entra no Tailwind theme |
| i18n | `app/javascript/dashboard/i18n/locale/pt_BR/` (e `pt/`) | 40+ JSON |
| Models | `app/models/{contact,conversation,inbox,label}.rb` | **sem** Lead/Deal/Kanban nativos |

## Disciplina de fork (minimizar dor de rebase)

Regra de ouro: **adicionar, quase nunca editar.**

- **Arquivos NOVOS em namespace `ramon/`** (componentes Vue, rotas, models, controllers,
  migrations) → upstream nunca toca neles.
- **Edições só em pontos de registro** (poucos, previsíveis): registrar item no trilho
  (`Sidebar.vue`/config de navegação) e a seção no índice de rotas (`dashboard.routes.js`)
  — ~2-3 linhas em ~3 arquivos. Manter **`docs/FORK-PONTOS-DE-REGISTRO.md`** listando-os.
- **Nunca tocar `enterprise/`** (licença separada).
- **Git:** `upstream = chatwoot/chatwoot` como remote; nosso trabalho numa branch `ramon`
  rebaseada sobre cada **release tag**; smoke test após cada rebase.
- **Imagem:** build próprio fixado em **v4.15.1** substitui `chatwoot/chatwoot:latest` no
  `docker-compose.yml` da VPS. (Risco lateral atual: `:latest` pode puxar versão nova e
  migrar sozinho — corrigido ao fixar a tag.)

## Marca & design (resumo — fonte: design-ref §5)

Estética **escura + bronze**, sóbria, **sem segunda cor** (prioridade "Alta" é bronze, não
vermelho). Fundo `#120d09`, trilho `#0c0907`, acento `#c4a882`, primária `#754d2a`. Títulos
**Cormorant Garamond**, UI **Inter**, ícones linha estilo Lucide, **sem emoji**. Tokens
completos em `design-ref/_ds/ramon-antonio-brand-…/tokens/`. Conteúdo PT-BR; compliance OAB
(Prov. 205/2021) no que for público.

## Roadmap em fases (valor ↑ / risco ↓)

### Fase 0 — Fundação do fork *(infra; destrava tudo; sem UI)*
- Configurar `ramon-hub` como fork: remote `upstream`, branch `ramon`, aprofundar histórico
  o necessário pra rebase, `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Build próprio da imagem (Dockerfile do Chatwoot), **fixar v4.15.1**, ajustar o
  `docker-compose.yml` da VPS pra usar a imagem do fork.
- Smoke test: subir o fork (idêntico ao upstream) e validar que conversas/contatos atuais
  seguem intactos (mesmo Postgres).

### Fase 1 — A casa (rebrand + trilho) *(maior valor, menor risco)*
- **Rebrand:** tema escuro+bronze no Tailwind `theme/colors` + `_next-colors.scss`;
  logo/nome via `installation_config`; fontes Cormorant + Inter.
- **Trilho:** estender `Sidebar.vue` com grupos **INTERNOS** (Conversas, Intranet) e
  **EXTERNOS** (links `target="_blank"`, lista configurável).
- **Modo Intranet:** seção nova `routes/dashboard/ramon/` (namespace) com sidebar
  secundária e o **Centro de Comando** (shell com KPIs/placeholders).
- Resultado: app rebrandizado, trilho alternando Conversas ⇄ Intranet sem reload.

### Fase 2 — Funil / Kanban (entidade Lead nativa)
- Migration + model `app/models/ramon/lead.rb` (`stage`, `priority`, `benefit_type`,
  `sdr_id`, `closer_id`, FK p/ `Contact`/`Conversation`) no `chatwoot_production`.
- Controller/serializer `api/v1/accounts/ramon/leads`; store Vuex `store/modules/ramon/leads`.
- **Kanban (Conversas)** e **Funil (Intranet)** = mesma view, mesma fonte; drag-drop;
  espelho em tempo real via **ActionCable** (já usado pelo Chatwoot).
- "Abrir conversa" → navega pra conversa do lead (mini-chat flutuante = item de UX, validar
  depois).
- **Etapas** reusam o mapa canônico do funil atual. Migrar leads do Supabase → Postgres.

### Fase 3 — Painel do Lead (dentro da conversa)
- Estender `ContactPanel.vue` com componente de abas `ramon/` (Resumo / Histórico /
  Documentos) ocupando ~metade da conversa.
- Score/temperatura/fase como **custom attributes** (renderização nativa) e/ou campos do
  `Lead`. Documentos via Active Storage (status recebido/pendente).

### Fase 4 — Inteligência & integrações
- Portar scoring e qualificação por IA (pgvector já disponível) pro Rails/worker.
- Módulos "Agentes de IA / Base de Conhecimento / Prompts".
- Integrações: AdvBox, Meu INSS/CNIS, Google Agenda (escopo a definir — ver pendências).
- **Aposentar o Supabase** e o container Next.js quando o último módulo migrar.

## Pendências a resolver por fase (não bloqueiam Fase 0/1)

- **B. Integrações:** AdvBox tem API (sync de leads/processos) ou é só atalho externo?
  Meu INSS/CNIS é anexo manual? Google Agenda é leitura ou escrita?
- **C. IA:** o que entrega primeiro — triagem de iniciais (jurídico), qualificação de lead
  (comercial) ou respostas sugeridas no atendimento?
- **D. Permissões/papéis:** usar papéis nativos do Chatwoot (`customRole`) ou modelo próprio
  pra SDR/closer/advogado/gestor?
- **E. Jurídico:** "Triagem de Iniciais"/"Histórico" usam o mesmo `Lead` do funil comercial
  ou entidade separada?
- **Mapa de etapas e pesos do score:** calibrar pela dor real na migração (Fase 2/4).

## Riscos e mitigação

- **Rebase com upstream (o maior):** footprint mínimo + namespace `ramon/` + lista de
  pontos de registro + rebase em release tags + smoke test. Fork é manutenção contínua —
  aceita como custo da escolha.
- **Esforço de re-plataformar a inteligência (scoring/Kit/IA):** mitigado pela **transição
  faseada** — estrutura primeiro, inteligência módulo a módulo, sem big-bang.
- **Capacidade da VPS:** dados de funil são pequenos; consolidar tende a *aliviar* (o
  container Next.js sai ao final). `pgvector` já habilitado p/ IA.
- **`:latest` migrar sozinho antes do fork:** fixar a tag na Fase 0.

---

*Próximo passo após aprovação: gerar o plano de implementação (writing-plans) começando
por **Fase 0 + Fase 1** (fundação do fork + rebrand/trilho), que é o pacote de maior valor
e menor risco.*
