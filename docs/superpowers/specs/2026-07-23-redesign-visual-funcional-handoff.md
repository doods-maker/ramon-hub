# Handoff: Ramon Hub — Redesign visual e funcional

## Overview
Pacote de redesign do **ramon-hub** (fork do Chatwoot v4.15.1, branch `ramon` de `doods-maker/ramon-hub`). Cobre: Centro de Comando ("Cockpit do SDR"), Funil/Kanban denso com ações em lote, múltiplos quadros + raias por tese, Painel do lead com abas, Esteira "Modo Foco", SLA de 1º contato, Cmd+K com ações, Agenda no Cockpit, ZapSign em destaque, análise de motivos de perda, resumo diário (ntfy/e-mail), Portal do cliente, Copiloto noturno, Placar de TV (/tv) e Radar de prescrição.

## About the Design Files
`Melhorias Ramon Hub.dc.html` é uma **referência de design em HTML** (canvas com mockups estáticos), não código de produção. A tarefa é **recriar estes designs dentro do codebase existente** — Vue 3 (`<script setup>`, Composition API) + Tailwind (tokens em `theme/colors.js`, mapeados a CSS vars), seguindo os padrões do fork descritos abaixo. **Não usar CSS custom nem estilos inline** no app real (regra do AGENTS.md do repo: Tailwind only).

O arquivo tem turnos empilhados (mais novo no topo). Ids dos mockups:
- `5a` Placar de TV final (versão aprovada — substitui `4c`)
- `4a` Portal do cliente · `4b` Copiloto noturno · `4d` Radar de prescrição
- `3a` SLA 1º contato · `3b` Cmd+K · `3c` Agenda no Cockpit · `3d` ZapSign destaque · `3e` Perdas por tese · `3f` Resumo diário
- `2a` Quadros salvos · `2b` Raias por tese
- `1b` Cockpit do SDR · `1d` Funil denso · `1f` Painel do lead com abas · `1h` Esteira Modo Foco
- `1a/1c/1e/1g` são recriações do estado ATUAL (baseline de comparação — não implementar)

## Fidelity
**High-fidelity.** Cores, tipografia, espaçamentos e copy são finais. Recriar pixel-perfect usando as classes Tailwind do fork (`bg-n-solid-2`, `text-n-slate-11`, `border-n-weak`, `bg-n-iris-9` etc.) — os hex abaixo existem só para mapear de volta aos tokens.

## Decisão transversal de tema (dark)
Hoje os cards usam `--solid-2` (#1d1e24, frio/azulado) sobre o fundo quente #262320 (`_ramon-brand.scss`). **Corrigir adicionando overrides no bloco `.dark` de `_ramon-brand.scss`:**
```scss
--solid-1: 46 43 39;   // #2e2b27
--solid-2: 46 43 39;   // #2e2b27 (cards quentes)
--solid-3: 51 48 44;   // #33302c
--border-weak: 61 55 47; // ~rgba(201,169,124,.10) sobre #262320
```
Bronze fica reservado a CTA, foco, valores monetários e estado ativo.

## Design Tokens (dark — os que os mocks usam)
| Papel | Hex | Token do fork |
|---|---|---|
| Fundo do app | #262320 | `--background-color` |
| Trilho/modo foco | #1e1b19 | `--ramon-rail` |
| Sidebar / coluna kanban | #2b2825 | `--surface-1` / `--ramon-column` |
| Card (novo, quente) | #2e2b27 → #33302c | `--solid-2` (override acima) |
| Texto alto contraste | #ece7df | `--iris-12` / slate-12 |
| Texto médio | #b0a99e–#b0b4ba | slate-11 |
| Texto fraco | #8d867d / #77716a | slate-10/9 |
| Bronze primário (botões) | #8a5c33, hover #7a5029 | `--iris-9/10` |
| Dourado (acento/ativo) | #c9a97c | `--iris-11` |
| Borda bronze suave | rgba(201,169,124,.10–.30) | usar `border-n-weak` pós-override |
| Perigo | #e54666 / texto #ff949d | ruby-9/11 |
| Alerta | #ffc53d / texto #ffca16 | amber-9/11 |
| Sucesso | #12a594 / texto #0bd8b6 | teal-9/11 |
| Light (portal/e-mail) | fundo #faf3e8, painel #3b2a1c, primário #754d2a, sunken #f5e6cc, texto #26211b | design system da marca |

Tipografia: títulos e números grandes **Cormorant Garamond** 500–700 (`font-cormorant`, já no tailwind.config); UI **Inter**. Radius: 8–14px (cards 12–14, pills 999). Datas semânticas em chips: verde = futuro, âmbar = hoje/dentro do SLA, vermelho = vencido/prescrevendo.

## Screens / Views — o que construir e onde

### 1. Cockpit do SDR (mock `1b`) — substitui o CommandCenter
Arquivo: `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue` (+ store `ramonDashboard`).
- Header: saudação Cormorant 32px + data; à direita **meta do dia** (barra 160px, gradiente #8a5c33→#c9a97c, "5/12") e CTA "Começar o dia" (bronze, 38px, leva à Esteira).
- **KPI strip** (grid 6): Vencidas (ruby), Para hoje, Parados (âmbar), Novos da LP, Ganhos na semana (teal), Previsão ponderada (dourado). Cards 12px padding, número 20px/600.
- Grid 1.5fr/1fr: esquerda **"Sua fila agora"** — hero card do 1º item da fila (nome Cormorant 26, chips de risco, valor dourado, ações: Abrir conversa / Rascunho da IA / Feito, hint "Espaço pula · F feito") + lista dos próximos (linha: dot de severidade 6px, nome, motivo, valor). Fonte de dados: mesma união tasks_overdue+stalled já feita em `followUpQueue`.
- Direita: **Funil · conversão** (barra segmentada por etapa + linhas com "↳ N% avançam" entre etapas) e **Semana · time** (ranking: avatar, ganhos teal, ações).
- Novos dados do endpoint `ramon_dashboard`: meta diária, previsão ponderada (já existe por stage: Σ valor×probability), conversão etapa→etapa, ranking por agente.

### 2. Funil denso (mocks `1d`, `2a`, `2b`)
Arquivos: `KanbanBoard.vue`, `KanbanColumn.vue`, `LeadCard.vue`, `KanbanFilters.vue`, `SavedViews.vue`, store `leads`.
- **Card compacto (2 linhas):** linha 1 = checkbox (14px, marca bronze) + nome + valor compacto dourado à direita; linha 2 (indent 22px) = próxima ação com dot semântico ("● hoje: 1º contato" âmbar, "● venceu: …" ruby, "● amanhã: retorno" teal) + metadados discretos. Risco = **borda esquerda 3px** (âmbar parado / ruby prescrevendo). Ações rápidas (Conversa/Tarefa/Dossiê) aparecem no hover.
- **Header da coluna:** nome + "N · R$ X mil" + alerta agregado à direita ("3 sem contato >24h" âmbar, "R$ 1,4 mil/mês prescrevendo" ruby). Top strip 2px na cor da etapa (manter).
- **Visões salvas como abas** (segmented control #1e1b19/#33302c) + **filtros como chips removíveis** ("SDR: Eduardo ✕") + resumo à direita ("32 leads · R$ 616 mil · previsão R$ 187 mil").
- **Barra de ações em lote** (fixa embaixo ao selecionar): "N selecionados | Mover etapa ▾ · Atribuir SDR ▾ · Agendar follow-up · Rodar triagem IA · Esc cancela". Backend: reusar `BulkActionsJob`.
- **Quadros salvos (`2a`):** promover SavedViews a entidade nomeada (nome, cor, filtros serializados, por usuário via `ui_settings` ou tabela própria). Dropdown no título: "Quadro: Restabelecimento B31 ▾" com lista (cor + contagem) + "Novo quadro (a partir dos filtros atuais)". Quadro persiste filtros, colunas colapsadas e ordenação.
- **Raias por tese (`2b`):** toggle de visualização Colunas / Raias / Lista. Raia = linha horizontal (card #2b2825) com célula-resumo à esquerda (tese, "N · R$ X", alertas) e uma coluna de cards por etapa; seletor "agrupar por: tese · dono · canal · prioridade". Drag entre colunas continua dentro da raia.

### 3. Painel do lead (mock `1f`)
Arquivo: `LeadConversationPanel.vue` (+ `LeadFields.vue`, `useLeadPanelSections.js` vira tabs).
- **Cabeçalho fixo:** nome Cormorant 21px; chips: etapa (editável, dropdown inline), prescrição (ruby sólido), valor; 4 ações fixas: WhatsApp (bronze primário), + Tarefa, Dossiê 30s, Resolver (teal soft).
- **Abas** (substituem acordeões): Resumo · Playbook · IA · Simulador · Histórico. Dot de status na aba: âmbar = triagem aguardando humano, verde = simulação/kit prontos. Aba **IA** unifica Copilot + Triagem + Kit.
- **Resumo:** card "Próxima ação" no topo (gradiente #332e28→#2e2b27, borda âmbar se vencida; botões Feito ✓ / Adiar 1d / Reagendar — API `lead_tasks` complete/update); card "Resumo da IA" (com timestamp + Sugerir resposta/Atualizar); grid 2-col de leitura (Benefício, Tese, SDR/Closer, DCB — vermelha se prescrevendo, Telefone, CPF); link "editar todos os campos ▾" abre o formulário completo atual (LeadFields); Notas por último.
- **ZapSign (`3d`):** quando `zapsignEligible`, cartão destacado logo abaixo das ações do cabeçalho — título "Contrato ZapSign · tese elegível", estado "faltam N dados" listando os campos (CPF, nascimento) com CTA "Completar dados"; botão "Gerar contrato" desabilitado até completar; depois de gerado mostra link + copiar no mesmo cartão.

### 4. Esteira Modo Foco (mock `1h`)
Arquivo: `pages/Esteira.vue`.
- Fundo **#1e1b19** full-bleed. Topo: título + barra de progresso "5 de 12" (gradiente bronze) + "R$ 391 mil em jogo" + "Sair do foco · Esc".
- Grid 1.3fr/1fr. Esquerda, card hero (gradiente #33302c→#2b2825, borda bronze .25): "Ação sugerida · Ligar", nome Cormorant 34, chips de motivo, **bloco "Script do playbook"** (busca itens da tese do lead — API `theses` show, seção `abertura`/`objecao`; botão copiar), ações com kbd visível: Abrir conversa (C), Feito (F, teal), Adiar (A), Pular (Espaço).
- Direita: **Última mensagem** (bolha, via conversa do lead), **Simulador · última simulação** (valor Cormorant 24 + parâmetros; persistir último resultado da `lead_simulacoes`), **Depois desta** (3 próximos com dot de severidade).

### 5. SLA de 1º contato (mock `3a`)
- Config por inbox (junto do toggle `auto_create_lead` em `Settings.vue` da inbox): "SLA de 1ª resposta: 60 min".
- Card na coluna Novo: pill de timer à direita do nome — âmbar regressivo dentro do SLA ("41min"), ruby estourado ("2h 47min"), teal respondido ("respondido 12min"); borda esquerda acompanha. Card estourado ganha CTAs "Responder agora" / "Rascunho da IA".
- Header da coluna: "2 fora do SLA" (ruby). Cockpit: KPIs "Fora do SLA" e "Tempo médio de 1ª resposta hoje". Estourou → lead sobe na Esteira.

### 6. Cmd+K com ações (mock `3b`)
- Estender o command palette existente: seção "Leads" (avatar iniciais, nome, "etapa · benefício · valor", ↵ abrir) + seção "Ações com <lead>" no item selecionado: Mover para etapa… (M), Criar tarefa… (T), Abrir Dossiê 30s (D), Simular benefício (S). Backend: `search_service` já resolve leads (`filter_leads`).

### 7. Agenda no Cockpit (mock `3c`)
- Card "Hoje na agenda" na coluna direita do Cockpit, acima do funil: linhas com bloco de hora (52px, bronze soft para a próxima, cinza para as demais), nome, "tipo · responsável · origem", chips Kit do Closer / Dossiê / Simulação; rodapé "ver semana inteira → Agenda". Dados: `lead_tasks` kind `meeting` do dia.

### 8. Perdas por tese (mock `3e`)
- Bloco no Cockpit (admin) ou aba em Config. do funil: por tese, barra empilhada horizontal (22px) de `lost_reason` com gradações de ruby (#e54666 → rgba .55 → .3), header "N perdas · ↑/↓ % vs. trimestre" e linha "Sinal:" (dourada) com leitura acionável. Janela 90d, seletor "por tese ▾".

### 9. Resumo diário (mock `3f`)
- **Push ntfy 8h** (SDR): título "Ramon Hub · seu dia", corpo 1 linha: "3 tarefas vencidas · 2 fora do SLA · reunião 15h (Antônio) · R$ 391 mil em jogo". Reusar `Ramon::NtfyPushJob` + `schedule.yml`.
- **E-mail digest 8h** (gestão), tema light da marca: header #3b2a1c com título Cormorant + data dourada; 4 stats (novos / ganhos+valor teal-escuro #0d7a6a / perdidos+motivo #b3364f / 1ª resposta média #7d5432) em Cormorant 22; box "Atenção hoje" em #f5e6cc; link "Abrir o Centro de Comando →".

### 10. Portal do cliente (mock `4a`)
- Rota pública com token por lead (link mágico, sem senha; throttle no rack_attack). Tema **light da marca**: fundo #faf3e8, header #3b2a1c com monograma bronze.
- Conteúdo: "Olá, <nome>" eyebrow; status atual como headline Cormorant 26 + divisor gradiente bronze 56×3px; **timeline vertical** (etapas: check bronze sólido = concluída, anel bronze + dot = atual com pill "agora", cinza = futura) alimentada por `lead_activities` traduzidas para linguagem de cliente; **card de pendência** ("Falta 1 documento") com CTA pill bronze "Enviar documento" (upload → conversa) — fonte: `DocChecklist`.
- Rodapé compliance fixo: "Conteúdo informativo sobre o andamento do seu atendimento. Não substitui a orientação jurídica individual de um(a) advogado(a)." Sem valores, sem promessa de resultado.

### 11. Copiloto noturno (mock `4b`)
- Job noturno (5h, `schedule.yml`) varre leads parados/sem resposta e gera sugestões via `Ramon::LlmClient`: **Rascunho** (mensagem pronta), **Mover etapa** (com justificativa), **Alerta** (ex.: menção a concorrente). Tabela nova `copilot_suggestions` (lead, tipo, payload, status).
- UI: bloco "Enquanto você dormia" no topo do Cockpit — header com ícone bot em tile gradiente bronze, "revisou 32 leads às 5h · 8 sugestões", botão "Aprovar todas (8)"; cards por sugestão com tag colorida (Rascunho dourado / Mover etapa âmbar / Alerta ruby) e ações Enviar·Editar·Descartar / Aplicar / Subir na esteira. **Nada é enviado sem aprovação humana.**

### 12. Placar de TV — /tv (mock `5a`, versão final)
- Rota `/tv` sem chrome, **1280×720 escalável** (transform scale para caber em qualquer 16:9), atualização via ActionCable (`lead_updated`).
- Topo: eyebrow "RAMON ANTONIO · JULHO" (tracking .24em dourado) + "ao vivo · hh:mm"; hero **"R$ 312 mil"** Cormorant 88 + meta (barra + 78% + "faltam N dias úteis") + placar "Hoje" (ganhos teal / novos / 1ª resposta, Cormorant 32).
- Centro-esquerda, **"Por tese"**: linhas separadas por hairline bronze (.10) — dot da cor, nome 16px + subnota colorida só quando há história ("2 prescrevendo" ruby, "melhor conversão do mês" teal, "2 parados há +10d" âmbar, "estável" cinza); 3 blocos numéricos à direita: leads (Cormorant 26 + "leads · +N na semana"), ganhos (Cormorant 26 teal + "ganhos · N%"), valor (17px teal). Rodapé: funil ativo em 1 linha de texto.
- Direita: cards Corrida do mês (posições Cormorant), Dinheiro prescrevendo (borda ruby, Cormorant 34 ruby), Próximo compromisso (hora dourada). Base: ticker "Agora: <closer> fechou <lead> — R$ X · <benefício>" com dot teal.
- Dados: `ramon_dashboard` + `theses` agregados; rotação de destaque opcional a cada 30s.

### 13. Radar de prescrição (mock `4d`)
- Página nova na Intranet (ou bloco de gestão): header Cormorant + linha-resumo "R$ 11.240/mês prescrevendo em 8 leads · R$ 23.700/mês entram em risco em 90 dias".
- Lista ordenada por sangramento: grid nome/subnota (benefício · DCB · etapa — incluir **leads perdidos** com "Perdemos (reativar?)" âmbar) + barra de prazo consumido (ruby >75%, âmbar antes) + "R$ X/mês" à direita. Cálculo: helper `prescription.js` existente sobre toda a base.
- CTA "Criar campanha de resgate (N)" — integra com campanhas respeitando o guard LGPD `consent_marketing` já implementado.

## Interactions & Behavior
- Animações contidas: 140–220ms, `cubic-bezier(0.4,0,0.2,1)`; hover em card = borda bronze (nunca apagar borda de risco); press scale(0.97).
- Atalhos: board j/k/e/c (manter); Esteira F/A/C/Espaço/Esc; Cmd+K M/T/D/S; lote Esc cancela.
- Undo de movimentação por toast (5s) — manter padrão atual.
- Estados de erro sempre com retry explícito (padrão do fork); skeletons nos primeiros loads.

## State Management
- Novos módulos/campos Vuex: `savedBoards` (quadros), `copilotSuggestions`, SLA no `leads` (deadline por lead), agregados novos no `ramonDashboard` (meta, previsão, conversão, ranking, agenda do dia, perdas por tese).
- Realtime: reusar broadcasts `lead_created/lead_updated`; TV e Cockpit assinam o mesmo canal.

## Assets
- Monograma: `public/brand-assets/ramon-monogram.png` (nos mocks, placeholder "RA" em tile bronze — usar o PNG real).
- Ícones: Lucide (classes `i-lucide-*` já usadas no fork), stroke 1.6–1.7.
- Fontes: Cormorant Garamond + Inter (já carregadas).

## Files
- `Melhorias Ramon Hub.dc.html` — canvas com todos os mockups (abrir no navegador; ids `1a`–`5a` ancoráveis via `#id`).

## Ordem sugerida de implementação (menor risco → maior)
1. Override de tema (solid-2 quente) — 1 arquivo SCSS, efeito em todo o app
2. LeadCard denso + alertas de coluna (`1d`)
3. Painel do lead com abas + ZapSign destaque (`1f`, `3d`)
4. Cockpit (`1b`) + Agenda (`3c`) + SLA (`3a`)
5. Esteira Modo Foco (`1h`)
6. Quadros salvos (`2a`) → raias (`2b`) · lote (`1d`)
7. Cmd+K ações (`3b`) · Resumo diário (`3f`) · Perdas (`3e`)
8. TV `/tv` (`5a`) · Radar (`4d`) · Copiloto noturno (`4b`) · Portal do cliente (`4a`)

---

## Decisões de implementação (sessão 23/07, Fable)

- Metas: sem tabela nova — `RAMON_DAILY_GOAL` (default 12, numerador = esteira done_today) e `RAMON_MONTHLY_GOAL_BRL` (TV/Cockpit; sem env = barra oculta). GATE Eduardo: definir valores reais.
- Conversão etapa→etapa: derivada de `lead_activities` kind `stage_changed` (janela 90d) — % de leads que saíram da etapa para frente. Aproximação documentada no controller.
- SLA por inbox: segue o padrão do toggle `auto_create_lead` (fork-ponto em Settings da inbox); fallback env `RAMON_SLA_FIRST_RESPONSE_MINUTES`.
- Última simulação: persistida em `custom_attributes.ultima_simulacao` via PATCH deep_merge existente (sem migração).
- Portal do cliente: coluna `portal_token` no Lead + rota pública server-rendered (ERB, tema light), throttle rack_attack, rodapé compliance fixo.
- Copiloto noturno: tabela nova `copilot_suggestions` + job cron 5h BRT; nada é enviado sem aprovação humana.
- Bulk de leads: case `Lead` no bulk_actions_controller + job próprio (não existia).
