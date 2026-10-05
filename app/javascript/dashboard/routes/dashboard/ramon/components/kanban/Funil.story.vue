<script setup>
// Story do Funil (aprovação visual por print, claro/escuro). Sem rede:
// window.axios responde com dados de exemplo por URL. Estados internos do
// board (painel de filtros, menus) abrem por clique depois de montar.
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import KanbanBoard from './KanbanBoard.vue';
import WonValueModal from './WonValueModal.vue';
import LostReasonModal from './LostReasonModal.vue';
import NewLeadModal from './NewLeadModal.vue';
import RemoveStageModal from './RemoveStageModal.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();
const emDias = n => new Date(Date.now() + n * DIA).toISOString();
const emMin = n => new Date(Date.now() + n * 60000).toISOString();
const emDiasAs = (n, h) => {
  const d = new Date(Date.now() + n * DIA);
  d.setHours(h, 0, 0, 0);
  return d.toISOString();
};

const STAGES = [
  { id: 1, name: 'Novo', color: '#64748b', position: 1, probability: 10 },
  {
    id: 2,
    name: 'Qualificação',
    color: '#0ea5e9',
    position: 2,
    probability: 25,
    stalled_after_days: 3,
  },
  { id: 3, name: 'Reunião', color: '#8b5cf6', position: 3, probability: 50 },
  {
    id: 4,
    name: 'Assinatura',
    color: '#ec4899',
    position: 4,
    probability: 75,
  },
  {
    id: 5,
    name: 'Ganho',
    color: '#22c55e',
    position: 5,
    probability: 100,
    is_won: true,
  },
  {
    id: 6,
    name: 'Perdido',
    color: '#ef4444',
    position: 6,
    probability: 0,
    is_lost: true,
  },
];

const base = {
  open_tasks_count: 1,
  channel: 'whatsapp',
  source: 'Meta Ads',
  stage_entered_at: diasAtras(1),
  created_at: diasAtras(10),
};

const LEADS = [
  {
    ...base,
    id: 1,
    name: 'Maria Aparecida Souza',
    lead_stage_id: 1,
    position: 1,
    value: null,
    thesis_id: 2,
    thesis_name: 'BPC/LOAS',
    benefit_type_name: 'B87',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    docs_total: 5,
    docs_received: 1,
    conversation_id: 101,
    contact_phone: '+55 48 99812-3456',
    open_tasks_count: 0,
    sla: { due_at: emMin(41), minutes: 60 },
    stage_entered_at: diasAtras(0),
  },
  {
    ...base,
    id: 2,
    name: 'José Ribeiro da Silva',
    lead_stage_id: 1,
    position: 2,
    value: 12000,
    thesis_id: 3,
    thesis_name: 'Auxílio-doença',
    benefit_type_name: 'B31',
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    docs_total: 4,
    docs_received: 0,
    conversation_id: 102,
    contact_phone: '+55 48 99654-1020',
    open_tasks_count: 0,
    sla: { due_at: emMin(-167), minutes: 60 },
    latest_triage: { status: 'awaiting_human' },
    stage_entered_at: diasAtras(0),
  },
  {
    ...base,
    id: 3,
    name: 'Ana Paula Martins',
    lead_stage_id: 1,
    position: 3,
    value: 9000,
    thesis_id: 4,
    thesis_name: 'Salário-maternidade',
    benefit_type_name: 'B80',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    conversation_id: 103,
    contact_phone: '+55 48 98841-7733',
    sla: {
      due_at: emMin(30),
      replied_at: emMin(-18),
      minutes: 60,
    },
    next_task_due_at: emDias(1),
    next_task_title: 'Pedir certidão de nascimento',
  },
  {
    ...base,
    id: 4,
    name: 'João Carlos Pereira',
    lead_stage_id: 2,
    position: 1,
    value: 18500,
    thesis_id: 1,
    thesis_name: 'Auxílio-acidente',
    benefit_type_name: 'B94',
    dcb_em: '2020-08-10',
    benefit_monthly_value: 1412,
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    docs_total: 5,
    docs_received: 3,
    conversation_id: 104,
    contact_phone: '+55 48 99120-4455',
    follow_up_count: 2,
    follow_up_last_at: diasAtras(2),
    stalled: true,
    stage_entered_at: diasAtras(4),
    next_task_due_at: emMin(120),
    next_task_title: 'Ligar para confirmar laudo',
  },
  {
    ...base,
    id: 5,
    name: 'Rosângela Ferreira',
    lead_stage_id: 2,
    position: 2,
    value: 45000,
    thesis_id: 5,
    thesis_name: 'Aposentadoria especial',
    benefit_type_name: 'B46',
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    docs_total: 6,
    docs_received: 2,
    conversation_id: 105,
    contact_phone: '+55 48 99702-3311',
    stage_entered_at: diasAtras(9),
    next_task_due_at: diasAtras(1),
    next_task_title: 'Cobrar PPP',
  },
  {
    ...base,
    id: 6,
    name: 'Carlos Eduardo Lima',
    lead_stage_id: 3,
    position: 1,
    value: 32000,
    thesis_id: 6,
    thesis_name: 'Aposentadoria por invalidez',
    benefit_type_name: 'B32',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    docs_total: 4,
    docs_received: 4,
    conversation_id: 106,
    contact_phone: '+55 48 99933-8080',
    // SLA de 1º contato vencido e nunca respondido, mas o lead já avançou
    sla: { due_at: diasAtras(3), minutes: 60 },
    stage_entered_at: diasAtras(2),
    next_task_due_at: emDiasAs(2, 14),
    next_task_title: 'Reunião',
    next_task_kind: 'meeting',
  },
  {
    ...base,
    id: 7,
    name: 'Luciana Alves',
    lead_stage_id: 3,
    position: 2,
    value: 22000,
    thesis_id: 7,
    thesis_name: 'Pensão por morte',
    benefit_type_name: 'B21',
    dcb_em: '2022-01-15',
    benefit_monthly_value: 1800,
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    docs_total: 5,
    docs_received: 4,
    conversation_id: 107,
    contact_phone: '+55 48 98455-6612',
    stage_entered_at: diasAtras(3),
    next_task_due_at: emDias(5),
    next_task_title: 'Enviar simulação',
  },
  {
    ...base,
    id: 8,
    name: 'Pedro Henrique Costa',
    lead_stage_id: 4,
    position: 1,
    value: 60000,
    thesis_id: 5,
    thesis_name: 'Aposentadoria especial',
    benefit_type_name: 'B46',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    docs_total: 6,
    docs_received: 5,
    conversation_id: 108,
    contact_phone: '+55 48 99011-2299',
    follow_up_count: 1,
    stage_entered_at: diasAtras(1),
    next_task_due_at: emDias(1),
    next_task_title: 'Enviar contrato no ZapSign',
  },
  {
    ...base,
    id: 9,
    name: 'Francisca Nunes',
    lead_stage_id: 5,
    position: 1,
    value: 38000,
    thesis_id: 1,
    thesis_name: 'Auxílio-acidente',
    benefit_type_name: 'B94',
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    docs_total: 6,
    docs_received: 6,
    won_at: diasAtras(3),
    docs_completos_em: diasAtras(2),
    sla: { due_at: diasAtras(9), minutes: 60 },
    conversation_id: 109,
    contact_phone: '+55 48 99876-5432',
    open_tasks_count: 0,
    stage_entered_at: diasAtras(3),
  },
  {
    ...base,
    id: 10,
    name: 'Sebastião Rocha',
    lead_stage_id: 5,
    position: 2,
    value: 27000,
    thesis_id: 2,
    thesis_name: 'BPC/LOAS',
    benefit_type_name: 'B87',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    docs_total: 5,
    docs_received: 5,
    won_at: diasAtras(12),
    docs_completos_em: diasAtras(10),
    contrato_limpo_em: diasAtras(3),
    conversation_id: 110,
    contact_phone: '+55 48 99345-1177',
    open_tasks_count: 0,
    stage_entered_at: diasAtras(12),
  },
  {
    ...base,
    id: 11,
    name: 'Antônio Carlos Mendes',
    lead_stage_id: 6,
    position: 1,
    value: 15000,
    thesis_id: 3,
    thesis_name: 'Auxílio-doença',
    benefit_type_name: 'B31',
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    lost_reason: 'Sem qualidade de segurado',
    lost_at: diasAtras(6),
    conversation_id: 111,
    contact_phone: '+55 48 98123-4567',
    open_tasks_count: 0,
    stage_entered_at: diasAtras(6),
  },
  // Fechados há meses: o Funil carregava todos os ganhos/perdidos da história.
  {
    ...base,
    id: 12,
    name: 'Valdir Nascimento',
    lead_stage_id: 5,
    position: 3,
    value: 52000,
    thesis_id: 5,
    thesis_name: 'Aposentadoria especial',
    benefit_type_name: 'B46',
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: 3,
    closer_name: 'Ramon Antonio',
    won_at: diasAtras(200),
    conversation_id: 112,
    contact_phone: '+55 48 99210-3344',
    open_tasks_count: 0,
    stage_entered_at: diasAtras(200),
  },
  {
    ...base,
    id: 13,
    name: 'Neusa Cardoso',
    lead_stage_id: 6,
    position: 2,
    value: 20000,
    thesis_id: 2,
    thesis_name: 'BPC/LOAS',
    benefit_type_name: 'B87',
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    lost_reason: 'Fechou com outro escritório',
    lost_at: diasAtras(150),
    conversation_id: 113,
    contact_phone: '+55 48 98700-5566',
    open_tasks_count: 0,
    stage_entered_at: diasAtras(150),
  },
];

const API = {
  lead_config: {
    stages: STAGES,
    channels: [
      { key: 'whatsapp', label: 'WhatsApp' },
      { key: 'instagram', label: 'Instagram' },
    ],
    sources: ['Meta Ads', 'Google', 'Indicação', 'Site'],
    lost_reasons: [
      { id: 1, name: 'Sem qualidade de segurado' },
      { id: 2, name: 'Fechou com outro escritório' },
    ],
    benefit_types: [
      { id: 1, name: 'B94' },
      { id: 2, name: 'B87' },
    ],
    priorities: [
      { id: 1, name: 'Alta' },
      { id: 2, name: 'Normal' },
    ],
  },
  leads: { payload: LEADS },
  agents: [
    { id: 1, name: 'Eduardo Schlata' },
    { id: 2, name: 'Gabriela Matos' },
    { id: 3, name: 'Ramon Antonio' },
  ],
  ramon_dashboard: {
    conversion: [
      { stage_id: 2, entered: 30, rate: 62 },
      { stage_id: 3, entered: 18, rate: 48 },
      { stage_id: 4, entered: 9, rate: 71 },
    ],
  },
  'leads/4': {
    ...LEADS[3],
    custom_attributes: { doc_status: {}, qualificacao_status: {} },
  },
  'leads/4/tasks': { payload: [] },
  'leads/4/notes': { payload: [] },
  'leads/4/activities': { payload: [] },
};

// Espelha a janela do index (Ramon::LeadRadar.closed_window): fechados só dos
// últimos 90 dias, salvo closed_all.
const fechadoRecente = lead => {
  const fechadoEm = lead.won_at || lead.lost_at;
  return !fechadoEm || Date.now() - new Date(fechadoEm) <= 90 * DIA;
};
const responder = async (url, config = {}) => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (path === 'leads' && !config.params?.closed_all)
    return { data: { payload: LEADS.filter(fechadoRecente) } };
  return { data: API[path] ?? {} };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const store = useStore();
// Sem router no harness: o papel (getCurrentRole) lê a conta da rota.
if (!store.hasModule('route'))
  store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  ui_settings: {
    ramon_lead_boards: [
      {
        id: 1,
        name: 'Meus leads',
        color: '#2563eb',
        filters: { agentId: 1 },
        collapsed: [],
        view: 'columns',
        groupBy: 'thesis',
      },
      {
        id: 2,
        name: 'Parados',
        color: '#db2777',
        filters: { stalled: true },
        collapsed: [],
        view: 'columns',
        groupBy: 'thesis',
      },
    ],
  },
  accounts: [{ id: 1, role: 'administrator' }],
});
store.dispatch('leadConfig/get');
store.dispatch('ramonDashboard/fetch');

// Estado salvo por variante: visualização, filtros, quadro ativo, colapso.
const estado = ({
  view = 'columns',
  groupBy = 'thesis',
  filtros = {},
  quadro = null,
} = {}) => {
  localStorage.setItem('ramon_kanban_view', JSON.stringify({ view, groupBy }));
  localStorage.setItem('ramon_lead_filters', JSON.stringify(filtros));
  localStorage.setItem('ramon_lead_board_active', JSON.stringify(quadro));
  localStorage.setItem('ramon_kanban_collapsed', '[]');
};
const clicar = seletor =>
  setTimeout(() => document.querySelector(seletor)?.click(), 2000);
// Menus fixos fecham no resize — e o print headless redimensiona a janela na
// captura. Só nas variantes de menu, o resize deixa de ser escutado.
const semResize = () => {
  const original = window.addEventListener.bind(window);
  window.addEventListener = (tipo, ...resto) =>
    tipo === 'resize' ? undefined : original(tipo, ...resto);
};

const colunas = () => estado();
const raias = () => estado({ view: 'lanes' });
const raiasSdr = () => estado({ view: 'lanes', groupBy: 'sdr' });
const lista = () => {
  estado({ view: 'list' });
  store.dispatch('leads/selectMany', [4, 6]);
};
const filtros = () => {
  estado({ filtros: { agentId: 1, channel: 'whatsapp' }, quadro: 1 });
  store.dispatch('leads/selectMany', [4, 6]);
  clicar('[data-testid="filters-toggle"]');
};
const fechadosTodos = () => estado({ filtros: { closedAll: true } });
const quadros = () => {
  estado({ quadro: 1 });
  clicar('[data-testid="board-dropdown-toggle"]');
};
const menuEtapa = () => {
  estado();
  semResize();
  clicar('[data-testid="stage-menu-toggle"]');
};
const sino = () => {
  estado();
  semResize();
  clicar('[data-testid="task-bell-toggle"]');
};
const gaveta = () => {
  estado();
  store.dispatch('leads/select', 4);
};
// Lote de 2 leads → Mover etapa → Ganho (5ª opção do menu), num clique só
// para a janela de confirmação já estar aberta no print.
const loteGanho = () => {
  estado();
  store.dispatch('leads/selectMany', [4, 6]);
  setTimeout(() => {
    document.querySelector('[data-testid="bulk-move-stage"]')?.click();
    document.querySelectorAll('[data-testid="bulk-stage-option"]')[4]?.click();
  }, 1500);
};
// Agente (não admin): etapas não são editáveis por ele.
const naoAdmin = () => {
  estado();
  store.commit(types.SET_CURRENT_USER, {
    ...store.getters.getCurrentUser,
    accounts: [{ id: 1, role: 'agent' }],
  });
};
</script>

<template>
  <Story title="Ramon/Funil" :layout="{ type: 'single', iframe: true }">
    <Variant title="Colunas" :init-state="colunas">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Raias" :init-state="raias">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Raias por SDR" :init-state="raiasSdr">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Lista" :init-state="lista">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Filtros" :init-state="filtros">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Fechados todos" :init-state="fechadosTodos">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Quadros" :init-state="quadros">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Menu da etapa" :init-state="menuEtapa">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Sino" :init-state="sino">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Gaveta" :init-state="gaveta">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Lote ganho" :init-state="loteGanho">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Não admin" :init-state="naoAdmin">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
      </div>
    </Variant>
    <Variant title="Ganho" :init-state="colunas">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
        <WonValueModal :initial-value="38000" />
      </div>
    </Variant>
    <Variant title="Perda" :init-state="colunas">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
        <LostReasonModal :lost-reasons="API.lead_config.lost_reasons" />
      </div>
    </Variant>
    <Variant title="Novo lead" :init-state="colunas">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
        <NewLeadModal />
      </div>
    </Variant>
    <Variant title="Remover etapa" :init-state="colunas">
      <div class="h-screen flex flex-col bg-n-background">
        <KanbanBoard />
        <RemoveStageModal
          :stage="STAGES[2]"
          :stages="STAGES"
          :leads-count="2"
        />
      </div>
    </Variant>
  </Story>
</template>
