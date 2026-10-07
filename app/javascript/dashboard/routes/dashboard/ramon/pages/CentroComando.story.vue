<script setup>
// Story do Centro de Comando + Esteira (aprovação visual por print,
// claro/escuro). Sem rede: window.axios responde com dados de exemplo por URL.
import { provide, reactive } from 'vue';
import { routeLocationKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import CommandCenter from './CommandCenter.vue';
import Esteira from './Esteira.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

// I-WD2: o Centro lê ?sugestoes= da rota (vindo da Visão geral).
const rota = reactive({ query: {} });
provide(routeLocationKey, rota);
const sugestoesFiltradas = () => {
  localStorage.setItem('ramon_night_copilot_expanded', '0');
  rota.query = { sugestoes: 'move_stage' };
};

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();
const hojeAs = (h, m = 0) => {
  const d = new Date();
  d.setHours(h, m, 0, 0);
  return d.toISOString();
};
// DCB de 6 anos atrás: já prescrevendo (janela de 60 meses).
const dcbAntiga = new Date(Date.now() - 6 * 365 * DIA)
  .toISOString()
  .slice(0, 10);

const DASHBOARD = {
  goal: { target: 8, done: 3 },
  forecast_total: 184000,
  today: {
    tasks_overdue: {
      count: 2,
      items: [
        {
          id: 11,
          lead_id: 1,
          lead_name: 'Maria Aparecida Souza',
          title: 'Cobrar CNIS',
          due_at: diasAtras(2),
          dcb_em: dcbAntiga,
          benefit_monthly_value: 1412,
        },
        {
          id: 12,
          lead_id: 2,
          lead_name: 'José Ribeiro da Silva',
          title: 'Retornar ligação',
          due_at: diasAtras(1),
        },
      ],
    },
    tasks_today: { count: 4, items: [] },
    stalled: {
      count: 3,
      items: [
        {
          id: 1,
          name: 'Maria Aparecida Souza',
          stage_name: 'Qualificação',
          days_in_stage: 5,
          conversation_id: 101,
          dcb_em: dcbAntiga,
          benefit_monthly_value: 1412,
        },
        {
          id: 3,
          name: 'Ana Paula Martins',
          stage_name: 'Reunião',
          days_in_stage: 7,
          conversation_id: 103,
          benefit_monthly_value: 2100,
        },
        {
          id: 4,
          name: 'Carlos Eduardo Lima',
          stage_name: 'Assinatura',
          days_in_stage: 4,
          conversation_id: 104,
        },
      ],
    },
    new_from_lp: { count: 5, items: [] },
  },
  week: {
    won: 3,
    won_since: diasAtras(0).slice(0, 10),
    nps: { media: 9.2, respostas: 6 },
  },
  funnel: [
    {
      stage_id: 1,
      name: 'Novo',
      color: '#64748b',
      count: 14,
      weighted_value: 21000,
    },
    {
      stage_id: 2,
      name: 'Qualificação',
      color: '#0ea5e9',
      count: 9,
      weighted_value: 34000,
    },
    {
      stage_id: 3,
      name: 'Reunião',
      color: '#8b5cf6',
      count: 6,
      weighted_value: 52000,
    },
    {
      stage_id: 4,
      name: 'Assinatura',
      color: '#ec4899',
      count: 3,
      weighted_value: 41000,
    },
    {
      stage_id: 5,
      name: 'Ganho',
      color: '#22c55e',
      count: 3,
      total_value: 36000,
      is_won: true,
    },
    { stage_id: 6, name: 'Perdido', color: '#ef4444', count: 4, is_lost: true },
  ],
  conversion: [
    { stage_id: 2, entered: 30, rate: 62 },
    { stage_id: 3, entered: 18, rate: 48 },
    { stage_id: 4, entered: 9, rate: 71 },
  ],
  team_week: [
    {
      user_id: 1,
      name: 'Eduardo Schlata',
      won_count: 2,
      won_value: 24000,
      activities_count: 38,
    },
    {
      user_id: 2,
      name: 'Gabriela Matos',
      won_count: 1,
      won_value: 12000,
      activities_count: 21,
    },
    {
      user_id: 3,
      name: 'Lucas Pereira',
      won_count: 0,
      won_value: 0,
      activities_count: 9,
    },
  ],
  agenda_today: [
    {
      id: 21,
      lead_id: 3,
      lead_name: 'Ana Paula Martins',
      due_at: hojeAs(9, 30),
      title: 'Reunião de fechamento',
      user_name: 'Eduardo',
      source: 'Meta Ads',
    },
    {
      id: 22,
      lead_id: 4,
      lead_name: 'Carlos Eduardo Lima',
      due_at: hojeAs(23, 50),
      title: 'Assinatura',
      user_name: 'Gabriela',
      source: 'Indicação',
    },
  ],
  losses_by_thesis: {
    window_days: 30,
    theses: [
      {
        thesis_id: 1,
        name: 'Auxílio-acidente',
        total: 10,
        prev_total: 7,
        reasons: [
          { reason: 'Sem qualidade de segurado', count: 6 },
          { reason: 'Fechou com outro', count: 2 },
          { reason: 'Sumiu', count: 1 },
          { reason: 'Outro', count: 1 },
        ],
      },
      {
        thesis_id: 2,
        name: 'BPC/LOAS',
        total: 4,
        prev_total: 6,
        reasons: [
          { reason: 'Renda acima', count: 2 },
          { reason: 'Sumiu', count: 2 },
        ],
      },
    ],
  },
  sla_today: { breached: 1, avg_first_response_minutes: 12 },
  // 30 snapshots diários (estoque do funil aberto), do mais antigo ao de hoje.
  history: Array.from({ length: 30 }, (_, i) => ({
    date: diasAtras(29 - i).slice(0, 10),
    leads_count: 20 + Math.round(i * 0.4) + (i % 3),
    value_sum: 90000 + i * 3200 + (i % 4) * 4000,
  })),
};

const SUGESTOES = {
  reviewed_count: 32,
  payload: [
    {
      id: 1,
      kind: 'draft',
      lead_name: 'José Ribeiro da Silva',
      run_at: hojeAs(3, 10),
      payload: {
        texto: 'Bom dia, José! Conseguiu separar o CNIS?',
        days_stalled: 3,
      },
    },
    {
      id: 2,
      kind: 'move_stage',
      lead_name: 'Ana Paula Martins',
      run_at: hojeAs(3, 10),
      payload: {
        justificativa: 'Reunião feita ontem, contrato enviado.',
        etapa_sugerida: 'Assinatura',
      },
    },
    {
      id: 3,
      kind: 'alert',
      lead_name: 'Maria Aparecida Souza',
      run_at: hojeAs(3, 10),
      payload: { justificativa: 'Parcelas prescrevendo desde março.' },
    },
  ],
};

const ESTEIRA = {
  board: { done_today: 3 },
  items: [
    {
      lead_id: 1,
      name: 'Maria Aparecida Souza',
      value: 16900,
      thesis_id: 1,
      stage_name: 'Qualificação',
      suggested_action: 'contact',
      conversation_id: 101,
      reasons: [
        { key: 'PRESCRIPTION_BLEEDING', params: { monthly: 1412 } },
        { key: 'TASK_OVERDUE', params: { title: 'Cobrar CNIS' } },
      ],
      last_message: {
        content: 'Oi doutor, vou ver se acho o papel do INSS e te mando.',
        at: Math.floor(Date.now() / 1000) - 3 * 3600,
        incoming: true,
      },
      ultima_simulacao: {
        atrasados: 38400,
        mensal: 1412,
        parametros: { der: '2024-03-12' },
        honorario_valor: 11520,
        em: diasAtras(4),
      },
    },
    {
      lead_id: 2,
      name: 'José Ribeiro da Silva',
      value: 12000,
      reasons: [{ key: 'STALLED', params: { days: 5 } }],
      suggested_action: 'follow_up',
    },
    {
      lead_id: 3,
      name: 'Ana Paula Martins',
      value: null,
      reasons: [{ key: 'NEW_FROM_LP', params: { source: 'auxílio-acidente' } }],
      suggested_action: 'reply',
    },
    {
      lead_id: 4,
      name: 'Carlos Eduardo Lima',
      value: 9000,
      reasons: [{ key: 'PRESCRIPTION_SOON', params: { months: 4 } }],
      suggested_action: 'task',
    },
  ],
};

const TESE = {
  id: 1,
  name: 'Auxílio-acidente',
  items: [
    {
      id: 1,
      section: 'abertura',
      content:
        'Oi, {nome}! Aqui é do escritório Ramon Antonio. Vi que você falou do acidente no trabalho — posso te fazer duas perguntas rápidas?',
    },
    {
      id: 2,
      section: 'objecao',
      content:
        'Entendo a dúvida sobre o custo: você só paga se o benefício sair, e o valor é combinado por escrito antes.',
    },
  ],
};

const API = {
  ramon_dashboard: DASHBOARD,
  copilot_suggestions: SUGESTOES,
  ramon_esteira: ESTEIRA,
  theses: [TESE],
  'theses/1': TESE,
  'conversations/101/ramon_copilot': {
    content: 'Oi, Maria! Conseguiu achar o papel do INSS?',
  },
};
const VAZIO = {
  ramon_dashboard: {
    ...DASHBOARD,
    today: {
      ...DASHBOARD.today,
      tasks_overdue: { count: 0, items: [] },
      stalled: { count: 0, items: [] },
    },
    agenda_today: [],
  },
  copilot_suggestions: { payload: [] },
  ramon_esteira: { board: { done_today: 7 }, items: [] },
};

let respostas = API;
const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  return { data: respostas[path] ?? {} };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  name: 'Eduardo Schlata',
  accounts: [{ id: 1, role: 'administrator' }],
});
store.dispatch('theses/get');

const vazio = () => {
  respostas = VAZIO;
};
// "Enquanto você dormia" abre recolhido; a variante aberta grava a escolha.
const copiloto = aberto => () =>
  localStorage.setItem('ramon_night_copilot_expanded', aberto ? '1' : '0');
const objecoes = () =>
  setTimeout(
    () =>
      document
        .querySelector('[data-testid="esteira-script-objections-toggle"]')
        ?.click(),
    2000
  );
</script>

<template>
  <Story
    title="Ramon/Centro de Comando"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Centro" :init-state="copiloto(false)">
      <div class="h-screen">
        <CommandCenter />
      </div>
    </Variant>
    <Variant title="Centro copiloto aberto" :init-state="copiloto(true)">
      <div class="h-screen">
        <CommandCenter />
      </div>
    </Variant>
    <Variant
      title="Centro sugestoes filtradas"
      :init-state="sugestoesFiltradas"
    >
      <div class="h-screen">
        <CommandCenter />
      </div>
    </Variant>
    <Variant title="Centro vazio" :init-state="vazio">
      <div class="h-screen">
        <CommandCenter />
      </div>
    </Variant>
    <Variant title="Esteira" :init-state="objecoes">
      <div class="h-screen">
        <Esteira />
      </div>
    </Variant>
    <Variant title="Esteira vazia" :init-state="vazio">
      <div class="h-screen">
        <Esteira />
      </div>
    </Variant>
  </Story>
</template>
