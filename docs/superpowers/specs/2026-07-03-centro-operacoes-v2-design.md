# Centro de Operações v2 — CRM de cadência + Centro de Comando
**ramon-hub · 03/07/2026 · spec aprovada em direção pelo Eduardo ("algo maior, melhor, mais validado"); detalhes aguardam revisão**

> Supera (não revoga) o plano mestre `comercial\docs\specs\2026-07-02-ramon-hub-plano-mestre.md`:
> absorve os itens 1–8, 13–15 (4b) e 17–19 (4c) numa arquitetura de produto validada por
> engenharia reversa de Breakcold, Salesforce Sales Cloud, Pipedrive, Close, HubSpot, Attio,
> folk, Lawmatics, Clio Grow e CRMs jurídicos BR (5 relatórios de pesquisa, sessão 03/07).

## 1. Tese do design

O hub já tem a vantagem estrutural que nenhum CRM de prateleira tem: **a conversa de
WhatsApp mora dentro do CRM**. O que falta é o que todos os CRMs de referência têm como
coração: a **camada de cadência** — o sistema cobra o operador, não o contrário. Hoje o
schema não tem nenhum campo de futuro (sem tarefa, sem follow-up, sem lembrete); o board
é uma foto. Este design transforma o hub em cobrador:

1. **Toda lead ativa tem próxima ação com data** (Pipedrive activity-based selling).
2. **O board denuncia sozinho** o que apodrece (Pipedrive rotting; Salesforce Kanban alerts).
3. **Perder ensina** — motivo de perda obrigatório + datas de ciclo (Salesforce validation).
4. **Dinheiro no board** — R$ ponderado por probabilidade de etapa (Salesforce forecast).
5. **A home é "o que está escapando"**, em fila executável (HubSpot task queues; Breakcold feed).
6. **Jurídico embutido** — checklist de documentos por tese com cobrança, dossiê no ganho
   (Lawmatics/Clio Grow; é onde CRM genérico falha para advocacia).

Invariantes: princípio de aprovação (IA/automação escreve **rascunho**, Eduardo envia);
fork merge-safe (arquivos novos em `ramon/`, core só em pontos de registro); PR/CI valida
(sem teste local); deploy só com OK explícito.

## 2. Entregas — dois PRs empilhados sobre o PR #20

Base: `feat/ramon-teses-playbooks` (PR #20, CI verde, aguardando merge). As tabelas
`theses`/`thesis_items` são fundação da Camada 4.

### PR A — `feat/ramon-cadencia-kanban` (Camadas 1+2)

**Migração (1 arquivo, com regen de schema via scratch DB na VPS):**
- Tabela **`lead_tasks`**: `account_id`, `lead_id`, `user_id` (criador), `title` (string),
  `kind` (string: `follow_up` | `document` | `meeting` | `other`), `due_at` (datetime),
  `completed_at` (datetime, null = aberta), timestamps. Índices: `(account_id, due_at)`,
  `(lead_id, completed_at)`.
- **`lead_stages`** += `stalled_after_days` (integer, null = nunca apodrece) e
  `probability` (integer 0–100). Seed/backfill: Novo 10/2d, Qualificação 20/3d, Reunião
  agendada 40/null, Reunião realizada 60/5d, Negociação 75/5d, Última chance 50/7d,
  Fechado 100/null, Perdido 0/null.
- **`leads`** += `stage_entered_at` (datetime, backfill = última activity `stage_changed`
  ou `created_at`), `won_at`, `lost_at` (datetime).
- **`lost_reasons`**: `account_id`, `name`, `position`. Seed: Sem viabilidade, Sumiu/não
  respondeu, Honorário, Foi para concorrente, Fora da área, Outro. (leads.lost_reason
  continua string — picklist alimenta a UI, campo aceita texto livre.)
- Histórico de transições: **não** cria tabela nova — `lead_activities.stage_changed` já
  registra de/para/quando; `stage_entered_at` dá o "agora". (Decisão anti-redundância.)

**Model/serviço:**
- `Lead`: callback em mudança de etapa seta `stage_entered_at = Time.current`; entrar em
  etapa `is_won` seta `won_at` (e pede `value` na UI); `is_lost` seta `lost_at`. Voltar a
  etapa ativa limpa `won_at`/`lost_at`.
- Exigência de motivo de perda fica **no controller do dashboard** (mover para `is_lost`
  sem `lost_reason` → 422), NÃO no model — o espelho label→etapa (`StageLabelSync`) e a
  captação pública não podem quebrar.
- `LeadTask` completável; ao completar, activity `task_completed`; criar gera `task_created`.
  Novos kinds em `lead_activities`.

**API:**
- `lead_tasks_controller`: nested em leads (`index/create`) + coleção da conta
  (`GET /leads/tasks?due=today|overdue|open`) + `PATCH complete` + `update/destroy`.
  Pundit: admin/agent.
- `leads#index` ganha filtros: `lead_stage_id`, `created_after`/`created_before`,
  `stalled=true` (dias na etapa > `stalled_after_days`), `no_open_task=true`.
- `permitted_params` += `custom_attributes` (jsonb liberado), `lost_reason` (já era).
- `lead_config#show` expõe `probability`/`stalled_after_days` das etapas + `lost_reasons`.
- `lead_stages` params += `probability`, `stalled_after_days`.

**Frontend (Kanban + card + painel):**
- **LeadCard**: idade na etapa ("3d"); borda âmbar quando `dias > stalled_after_days`,
  vermelha quando `> 2×`; badge "sem próxima ação" (nenhuma task aberta em etapa ativa);
  **sino de 1 clique** (menu: Amanhã / 3 dias / 1 semana / Escolher data → cria
  `lead_task` follow_up); botão wa.me quando lead tem telefone e não tem conversa;
  telefone clicável (copiar).
- **KanbanColumn**: header passa a mostrar contagem + R$ total + **R$ ponderado**
  (`Σ value × probability`).
- **KanbanFilters**: novos filtros etapa/período/parados/sem-próxima-ação; **Smart Views**:
  filtros salvos nomeados com contador, persistidos em `ui_settings` do usuário (mesmo
  mecanismo dos `external_shortcuts`, sem backend novo).
- **Drag para etapa perdida** → modal obrigatório de motivo (picklist + livre). **Drag para
  ganho** → modal pedindo `value` se vazio (pode pular — aviso, não trava).
- **NewLeadModal completo**: nome, telefone (busca contato existente; se já há lead aberto
  para o telefone → aviso "já existe" com link, em vez de duplicar), tese/benefício,
  origem, valor, prioridade.
- **LeadFields/painel**: bloco "Próximas ações" (tasks abertas, concluir em 1 clique;
  ao concluir, sugerir agendar a próxima — nunca obrigar); `lost_reason` visível/editável
  quando perdido.

### PR B — `feat/ramon-centro-comando` (Camadas 3+4, empilhado sobre A)

**Backend:**
- `ramon_dashboard_controller#show` (1 endpoint agregador, sem N+1; tudo escopado à conta):
  - `today`: tasks vencidas/de hoje; leads apodrecendo; leads ativos sem próxima ação;
    leads de LP (`source` presente, sem `conversation_id`) criados nas últimas 48h sem
    task nem nota; contagens + top N itens de cada lista (id, nome, etapa, dias).
  - `funnel`: por etapa — contagem, R$ total, R$ ponderado.
  - `week`: últimos 7 dias — criados/ganhos/perdidos por `source`; motivos de perda (30d).
- **Dossiê no ganho**: ao `won`, serviço gera **`lead_note` "📋 Dossiê de passagem
  (rascunho)"** com template W3 (tese, origem, honorário/valor, checklist de documentos,
  resumo da timeline) — rascunho para o Eduardo revisar/copiar; nada é enviado.

**Frontend:**
- **`RamonOverview` → Centro de Comando** (o placeholder morre): blocos **Hoje** (números
  grandes + listas clicáveis → abre Funil filtrado ou o drawer do lead), **Funil**
  (mini-funil numérico com R$ ponderado) e **Semana** (entradas × ganhos × perdidos por
  origem + motivos de perda). Sem gráfico complexo na v1.
- **Fila de retomada** ("Rodar follow-ups"): percorre em esteira os leads com task vencida
  ou apodrecendo — para cada um: abre o dock da conversa (se existir) + painel do lead
  com a aba Playbook; ações: Concluir (completa task + oferece próxima) / Pular / Encerrar
  lead. V1 = navegação item-a-item simples; sem envio automático de mensagem.
- **Checklist de documentos por tese** no painel do lead: deriva os itens da seção
  "documentos" dos `thesis_items` da tese do lead; estado por item
  (pendente/solicitado/recebido) persiste em `leads.custom_attributes.doc_status`
  (sem migração extra). Botão "cobrar pendentes" → monta **rascunho** de mensagem com os
  itens pendentes para copiar/colar no WhatsApp.
- **Guidance por etapa** (o "Path" do Salesforce, custo mínimo): a aba Playbook destaca a
  seção conforme a etapa (Qualificação→critérios, Negociação→objeções, pós-reunião→
  documentos); mapeamento estático no front.

## 3. Fora de escopo (desenhado, não construído hoje — gates externos)
ZapSign no fechamento · lifecycle pós-contrato do contato · ingestão Meta Ads/CAC
(System User token) · WhatsApp Cloud API (verificação Meta) · radares jurídicos
(DJEN/STJ/INSS) dentro do dashboard · MCP remoto do hub · import CSV · mobile fino ·
sequências automáticas de mensagem (OAB + aprovação: só rascunho, nunca envio).

## 4. Riscos e mitigação
- **Migração + seed/backfill** → regen do `schema.rb` via scratch DB na VPS (procedimento
  validado na F2.1a); PR A é o único com migração.
- **Espelho etapa↔label × validação de perda** → validação só no controller do dashboard.
- **`create(:account)` seeda funil nos specs** → specs nunca criam etapa com nome seedado;
  `Lead` tem default_scope de ordenação (`.last` não é o mais recente; DISTINCT+pluck
  exige `reorder(nil)`); máx 7 expectations/exemplo; `ENV.fetch`; eventos Vue camelCase;
  Vuex actions com `state: moduleState`.
- **Volume dos 2 PRs num dia** → execução por subagentes com review por tarefa; CI
  verificado por check-runs do commit exato (N/N completed, zero não-success, skipped ok).

## 5. Critérios de aceite (smoke pós-deploy)
1. Criar task pelo sino do card → aparece no painel e no bloco Hoje.
2. Lead parado além do limite da etapa fica âmbar; filtro "parados" o encontra.
3. Arrastar para Perdido exige motivo; para Fechado pede valor; `won_at`/`lost_at` gravados.
4. Coluna mostra R$ ponderado consistente com `value × probability`.
5. Smart View salva sobrevive a reload e mostra contador.
6. Novo lead com telefone repetido avisa duplicado.
7. Centro de Comando carrega com dados reais; listas clicáveis navegam certo.
8. Ganhar lead gera nota-dossiê rascunho.
9. Checklist de documentos aparece para lead com tese; "cobrar pendentes" gera rascunho.
10. Captação pública (LP) continua 201 + notificação (regressão).
