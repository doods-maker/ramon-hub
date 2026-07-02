# Fatia 1 — Painel do Lead na conversa (design)

**Data:** 2026-07-01
**Roadmap pai:** `2026-07-01-ramon-hub-roadmap-p1-crm-completo-design.md` (fatia 1 de 14)
**Fonte visual:** `design-ref/CLAUDE.md` §4 + `design-ref/screenshots/chat-painel.png`, `01-kanban.png`

---

## 1. Objetivo

Substituir o painel-tela-cheia de hoje (iframe `/embed/kit` da intranet Next.js legada) por
um **Painel do Lead nativo em Vue** dentro da conversa do Chatwoot, em **layout dividido**
(conversa à esquerda, painel ancorado à direita ~metade), com **abas**. É o primeiro tijolo
do "cockpit do lead": um contêiner de abas onde as fatias seguintes (follows, playbook, kit)
entram depois.

## 2. Estado atual (verificado no fork, branch `ramon`, 01/07)

- O painel direito da conversa é o `routes/dashboard/conversation/ContactPanel.vue` nativo —
  **não tem código nosso de lead**.
- O "Painel do Lead" que aparece na conversa hoje é o **iframe `/embed/kit`** (Dashboard App
  do Chatwoot apontando para a intranet Next.js legada) — configurado em runtime, não no repo.
- A lógica de editar lead por campo já existe em
  `routes/dashboard/ramon/components/kanban/LeadDrawer.vue` (A1), mas só é montada no
  `KanbanBoard.vue`. **A Fatia 1 reaproveita essa lógica.**

## 3. Escopo

**Entra:** abas **Resumo** e **Histórico**; substituição do painel nativo quando a conversa
tem Lead; auto-criação de Lead ao abrir + descarte; corte do iframe legado.

**NÃO entra (sub-fatias/fatias próprias):**
- **Aba Documentos** → sub-fatia própria: documentos do lead moram no **Google Drive**
  (não Active Storage/S3 — decisão do Eduardo, 01/07: não encher o disco da VPS), acessados
  da conversa; + resolver a **mídia recebida do WhatsApp** (que hoje nem flui — WhatsApp
  oficial é P3). Isso remove a necessidade de S3 do roadmap.
- **Temperatura (Quente/Morno/Frio)** e **checklist de qualificação** do mockup → adiados;
  o checklist casa com a **fatia 5 (playbook/triagem)**; temperatura é campo novo a calibrar.

## 4. Comportamento

### 4.1 Layout
- Conversa (mensagens) à esquerda; **Painel do Lead à direita ocupando ~metade** da área.
- Quando a conversa tem Lead, o painel direito **é** o Painel do Lead (substitui o nativo).
- As **ações nativas da conversa** (atribuir agente, prioridade, etiqueta, resolver, macros)
  são **embutidas dentro da aba Resumo**, reusando os componentes nativos — não somem.

### 4.2 Conversa sem Lead
- Ao **abrir** uma conversa sem Lead, cria-se um Lead na etapa **"Novo"** automaticamente
  (gatilho = abrir, sinal mais forte que só receber).
- Botão **"Não é lead / Descartar"** no painel → **apaga o Lead** (não move para "Perdido";
  "Perdido" é oportunidade real perdida, auto-criado que não vingou some limpo).
- **Higiene do funil (decisão 01/07):** criar-ao-abrir **respeita o espírito da flag 2B**
  no sentido de que o descarte é trivial; a criação em si é global ao abrir. (Se o volume
  incomodar, calibrar depois para respeitar `inboxes.auto_create_lead`.)

### 4.3 Abas
- **Resumo:** qualificação/dados do lead (etapa, tipo de benefício, prioridade, origem,
  valor, atribuição SDR/Closer, próxima ação, notas) — reusa `LeadDrawer` — **+** ações
  nativas da conversa embutidas.
- **Histórico:** timeline do lead — criado → **mudanças de etapa** → notas/marcos. Exige
  **registrar o histórico de etapas** (hoje não gravado; era follow-up pendente da A1) —
  entra nesta fatia.

### 4.4 Transição
- O painel nativo Vue substitui o **iframe `/embed/kit` legado**; o iframe é **cortado assim
  que a aba Resumo funcionar**. (Remover/aposentar o Dashboard App na config do Chatwoot.)

## 5. Forma técnica (a confirmar no plano, contra o código real)

- **Onde montar:** estender/condicionar o `ContactPanel.vue` para, quando a conversa tiver
  Lead (ou ao criá-lo ao abrir), renderizar um componente novo em `ramon/` (ex.:
  `ramon/components/conversation/LeadConversationPanel.vue`) com as abas. Namespace `ramon/`,
  edição mínima do core no ponto de registro (documentar em FORK-PONTOS).
- **Reuso:** extrair o miolo de campos do `LeadDrawer` para um componente compartilhado
  (drawer no Kanban + painel na conversa consomem o mesmo), evitando duplicação.
- **Ações nativas:** reusar os componentes nativos de ação da conversa (atribuição,
  prioridade, labels, resolve, macros) dentro do Resumo, sem reimplementar.
- **Dados:** reusar o serializer de Lead + `push_event_data` (realtime 2B) já existentes.
- **Histórico de etapas:** nova tabela/registro (ex.: `lead_stage_changes` ou log) gravado
  no callback de mudança de etapa do `Lead`; a aba Histórico lê dela.
- **Auto-criar ao abrir:** provavelmente ação no front ao abrir a conversa (garante Lead via
  API) ou hook no back; decidir no plano. Descartar = `DELETE /leads/:id`.

## 6. Riscos / decisões em aberto

- **Editar o `ContactPanel` nativo** é ponto sensível do core → manter a mudança mínima e
  condicional (fork merge-safe); documentar em `FORK-PONTOS-DE-REGISTRO.md`.
- **Largura ~metade:** o painel nativo do Chatwoot é estreito; ocupar ~metade exige ajuste
  de layout — calibrar visualmente pós-deploy.
- **Auto-criar ao abrir** pode gerar volume; mitigado pelo descarte de 1 clique. Reavaliar
  se poluir.
- **Reuso das ações nativas** dentro do Resumo pode acoplar a componentes internos do
  Chatwoot que mudam entre releases — preferir os mais estáveis.

## 7. Definição de pronto (Fatia 1)

- Painel do Lead nativo com abas **Resumo** (dados do lead + ações nativas) e **Histórico**
  (timeline com mudanças de etapa) no ar, em layout dividido.
- Conversa sem lead cria Lead em "Novo" ao abrir; botão "Não é lead" apaga.
- Iframe `/embed/kit` legado **cortado** da conversa.
- Verificação = feature branch → PR → CI (`run_foss_spec`); deploy com OK explícito do Eduardo.

## 8. Restrições (herdadas do roadmap)

Fork merge-safe (namespace `ramon/`, não tocar enterprise, rebase em tags); sem ambiente de
teste local (CI valida); deploy = pull + migrations com OK do Eduardo; nada no ar sem
aprovação explícita.
