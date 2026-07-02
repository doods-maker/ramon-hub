# Roadmap ramon-hub — CRM + Intranet completos (design/roadmap mestre)

**Data:** 2026-07-01
**Tipo:** Roadmap mestre (decomposição). Cada fatia ganha seu próprio spec → plano → implementação quando chegar a vez.
**Substitui como régua:** consolida e ordena o que falta; NÃO substitui os specs de fatia já escritos (dock, A3), apenas os posiciona.

---

## 1. Objetivo

Mapear **tudo que ainda falta** para o ramon-hub (fork pesado do Chatwoot v4.15.1) virar o
centro de comando comercial completo, e fixar a **ordem de execução em fatias pequenas**
(entrega → usa → calibra). Este documento é a régua das próximas sessões.

## 2. Escopo e prioridades (decididas pelo Eduardo, 01/07)

- **P1 — CRM comercial completo + todas as melhorias do chat** (foco total agora). Inclui
  migrar do Next legado (Supabase): playbook SDR por tese, triagem, Kit do Closer,
  atribuição/ROI — decisão do Eduardo: isso é parte essencial do "CRM pronto", não da
  inteligência.
- **P2 — Inteligência/IA:** base de conhecimento + DeepSeek, decidir Captain nativo vs.
  inteligência própria, IA no atendimento, e **aposentar o Supabase de vez**.
- **P3 — Integrações externas:** WhatsApp Cloud API oficial (Fase 2 do Chatwoot nunca
  feita), AdvBox, Google Agenda/Drive, Meu INSS. **Por último**; Eduardo ainda indeciso
  entre API oficial e alternativa.
- **Fora por ora:** módulo Jurídico (papel Advogado/Jurídico é reservado no modelo de
  permissões, mas o módulo não é construído agora).

**Sinal de negócio relevante:** haverá **contratação de time em seguida** → a "prontidão
para equipe" (papéis/permissões, teams, SLA, distribuição) entra no P1, não é adiada.

## 3. Estado atual (o que já está NO AR e validado)

- Fork base rebrandizado (bronze, dark default), rail de 2 mundos (Conversas ⇄ Intranet)
  com sidebars próprias.
- CRM: `Lead` nativo no Postgres; Kanban/Funil; realtime (ActionCable); auto-criação de
  lead por inbox; espelho bidirecional etapa ↔ label `fase-*`.
- Card rico do lead + gaveta lateral (A1); configuração do funil pela UI (A2/2D: etapas
  renomear/cor/reordenar/ganho-perda/remover, tipos de benefício, prioridades).

Specs de fatia já escritos e relacionados: `2026-06-30-ramon-hub-conversa-dock-botao-card-design.md`
(dock) e `2026-07-01-ramon-hub-A3-filtros-busca-totais-design.md` (A3).

## 4. Fonte de verdade visual

O mockup em `intranet-ramon/design-ref/` (`Ramon Antonio Hub.dc.html` + screenshots
`chat-painel.png`, `01-kanban.png`, `02-kanban.png`) e o `design-ref/CLAUDE.md` §4 são o
alvo de UX. Destaque §4: **Painel do Lead dentro da conversa = split (~metade), com abas.**

---

## 5. P1 — as 14 fatias, na ordem de execução

### Grupo A — Cockpit do Lead (costura chat ↔ CRM)

**Fatia 1 · Painel do Lead na conversa (o casco)** — *primeiríssima*
Substitui o painel-tela-cheia de hoje pelo **layout dividido** (conversa à esquerda,
Painel do Lead ancorado à direita ocupando ~metade), com **abas Resumo / Histórico /
Documentos** e edição do lead ali mesmo. Reusa o `LeadDrawer` já existente. O painel é um
**contêiner de abas**: as fatias 4–6 entram como abas/seções novas nele.
- *Resumo:* etapa no funil, qualificação (tipo de benefício, situação INSS, origem),
  checklist, contato, atribuição (SDR/Closer), próxima ação, notas.
- *Histórico:* timeline das interações.
- *Documentos:* **adiada para sub-fatia própria** — documentos do lead moram no **Google
  Drive** (decisão 01/07: não encher o disco da VPS), acessados da conversa; + resolver a
  **mídia recebida do WhatsApp** (que só flui quando o WhatsApp oficial existir, P3). Isso
  **remove a necessidade de S3**. Entrega 1 da fatia = abas **Resumo + Histórico**, cortando
  o iframe legado. Spec detalhado: `2026-07-01-ramon-hub-fatia-1-painel-lead-na-conversa-design.md`.

**Fatia 2 · Dock da conversa** — spec já escrita (`...conversa-dock-botao-card-design.md`)
A outra ponta: abrir/responder a conversa do lead num **dock flutuante no canto inferior
direito** sobre o Kanban, sem sair do mundo Intranet. Coexiste com a gaveta do lead.

**Fatia 3 · Cores das etapas + prioridade (paleta ampla)** — pequeno
Cada etapa com **cor própria e distinguível** (Novo, Qualificação, …) e **prioridade
colorida**, para leitura visual rápida. Amplia a paleta fixa da A2.
- **Decisão consciente (override):** contraria o `design-ref §5` ("sem segunda cor";
  "Alta = bronze"). A exceção vale para **etapas E prioridade** (Eduardo escolheu);
  a marca bronze segue no resto do produto.

**Fatia 4 · Follow-ups / próxima ação** — aba/seção no painel
SDR agenda retorno, define "próximo passo" e recebe lembrete. Mínimo: data + próximo passo
+ notificação in-app (ver §7 item 5).

**Fatia 5 · Playbook por tese + triagem** — aba no painel
Seleciona a "tese" do lead → roteiro de qualificação + checklist por tese. Migra do Next
legado (`leads.tese_id` já existia lá). Ver §7 item 3 (modelo de dados).

**Fatia 6 · Kit do Closer** — seção por etapa no painel
Roteiro / objeções / documentos por etapa, dentro do painel. Migra do Next legado.

### Grupo B — Funil completo

**Fatia 7 · A3 — filtros / busca / totais por coluna** — spec já escrita
Buscar lead; filtrar por dono/benefício/prioridade; total (R$ e nº) por coluna.

**Fatia 8 · A4 (2E) — campos custom do lead**
Campos configuráveis (coluna `leads.custom_attributes` jsonb já reservada).

**Fatia 9 · Atribuição / ROI de campanha**
Origem do lead (CTWA já captura) → retorno por campanha. Ver §7 item 4 (fonte do custo).

**Fatia 10 · Métricas do funil**
Conversão por etapa, tempo em etapa, valor no pipe. É a leitura gerencial e parte da
"definição de pronto".

### Grupo C — Prontidão para equipe (por causa da contratação)

**Fatia 11 · Papéis & permissões** — *custom, o mais pesado do grupo*
Distinguir **SDR, Closer, Gestor/Admin, Advogado/Jurídico** (este reservado). Nativo só tem
Agent/Admin (papéis custom são enterprise, que o fork não toca) → mecanismo próprio
(`ramon_role` no usuário + Pundit). Ver §7 item 1.
- Esboço: SDR vê seus leads/conversas, playbook, follows (talvez sem valores); Closer vê
  etapas de fechamento, Kit do Closer, valores/proposta; Gestor vê tudo e configura;
  Advogado reservado.

**Fatia 12 · Teams + caixas por time** — nativo, configurar
Requer SMTP ligado para convidar o time (§7 item 3-SMTP).

**Fatia 13 · SLA + prioridade + atribuição automática de conversa** — nativo, configurar

**Fatia 14 · Distribuição de leads entre SDRs** — começar manual, automatizar se doer

### Em paralelo (config, quase sem código)
Ligar o nativo do Chatwoot: **canned responses, macros, filtros salvos**.

---

## 6. Chat: nativo vs. custom (régua de decisão)

| Capacidade | Nativo atende? | Recomendação | Esforço |
|---|---|---|---|
| Respostas prontas (canned) | ✅ total | configurar e usar | baixo |
| Macros | ✅ total | configurar | baixo |
| Notas internas / @menções | ✅ já existe | nada a fazer | zero |
| Filtros salvos de conversa | ✅ total | configurar | baixo |
| Etiquetas | ✅ (já no espelho `fase-*`) | só organizar | baixo |
| Painel do Lead na conversa | ❌ | **custom (fatia 1)** | alto |
| Dock da conversa no Kanban | ❌ | **custom (fatia 2)** | médio |
| Follow-ups do lead | ⚠️ parcial (só snooze) | **custom leve (fatia 4)** | médio |
| Teams / caixas por time | ✅ total | **configurar (fatia 12)** | baixo |
| SLA / atribuição automática | ✅ total | **configurar (fatia 13)** | baixo |
| Papéis custom (SDR/Closer/…) | ❌ (só Agent/Admin) | **custom (fatia 11)** | alto |
| IA no atendimento (sugestão/resumo) | ✅ Captain nativo | **decidir na P2** | médio |

---

## 7. Riscos e decisões em aberto

| # | Decisão | Quando | Recomendação |
|---|---|---|---|
| 1 | Papéis custom (nativo só Agent/Admin) | antes da fatia 11 | `ramon_role` próprio + Pundit; não tocar enterprise |
| 2 | Documentos moram no **Google Drive** (decisão 01/07), não no servidor — **S3 descartado**. Falta resolver a **mídia recebida do WhatsApp** | sub-fatia de Documentos (mídia depende do WhatsApp, P3) | integrar Drive (OAuth/listar por lead); mídia do WhatsApp = ver quando o canal existir |
| 3 | SMTP (adiado) — convite de time exige e-mail | antes da fatia 12 | ligar SMTP quando for convidar o time |
| 4 | Fonte do custo de campanha (ROI, fatia 9) | fatia 9 | começar manual; integrar Meta Ads só se doer |
| 5 | Mecanismo de follow-up (fatia 4) | fatia 4 | mínimo: data + próximo passo + notificação in-app |
| 6 | Captain nativo vs. DeepSeek próprio (IA) | P2 | decidir na P2; não bloqueia o P1 |

## 8. Definição de "CRM pronto" (P1 completo)

Quando tudo isto estiver no ar:
- **Cockpit:** painel na conversa (abas) + dock + follows + playbook/tese + kit do closer.
- **Kanban = mockup:** cores por etapa e prioridade.
- **Funil:** filtros/totais + campos custom + atribuição origem→receita + métricas.
- **Equipe:** 4 papéis/permissões + teams + SLA + distribuição + SMTP p/ convites.
- **Nativo ligado:** canned + macros + filtros salvos.
- *(Supabase ainda vivo — aposentá-lo é P2.)*

## 9. Restrições de engenharia (valem para toda fatia)

- Fork merge-safe: código novo em namespace `ramon/`; evitar tocar core/enterprise; rebase
  em tags de release.
- **Sem ambiente de teste local** → verificação = feature branch → PR → CI (`run_foss_spec`).
- Deploy = pull da imagem + migrations, **com OK explícito do Eduardo a cada vez**.
- Regra de ouro: nada vai pro ar sem aprovação explícita do Eduardo.
- Filosofia: fatia pequena → usa de verdade → calibra pela dor real.

## 10. Próximos passos

1. Eduardo revisa este roadmap.
2. Ao aprovar, abrir o spec (ou plano, quando o spec já existir) da **Fatia 1 — Painel do
   Lead na conversa**, resolvendo antes a decisão de storage (§7 item 2) para a aba
   Documentos.
3. Executar em fatias, cada uma spec → plano → subagent-driven → PR/CI → deploy com OK.
