<script setup>
// Story do Extrato da variável, Radar de prescrição e Pós-venda — aprovação
// visual por print, claro/escuro. Sem rede: window.axios responde com dados
// FICTÍCIOS por URL. Papel (gestor × SDR/Closer) via auth/currentUser.
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Extrato from './Extrato.vue';
import RadarPrescricao from './RadarPrescricao.vue';
import PosVenda from './PosVenda.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const unidade = (dia, lead_id, lead_nome, evento, valor) => ({
  data: `2026-10-${String(dia).padStart(2, '0')}T14:00:00-03:00`,
  lead_id,
  lead_nome,
  evento,
  valor,
});

const LARISSA = {
  user: { id: 11, name: 'Larissa Bittencourt' },
  papel: 'sdr',
  meta: 40,
  rampa: false,
  contagem: 6,
  subtotal: 270,
  bonus: 150,
  degraus: 1,
  garantia_aplicada: false,
  total: 420,
  unidades: [
    unidade(1, 301, 'Maria de Lourdes Souza', 'reuniao_qualificada', 45),
    unidade(1, 302, 'Osmar Vieira da Cunha', 'reuniao_qualificada', 45),
    unidade(2, 305, 'Terezinha Medeiros Rocha', 'reuniao_qualificada', 45),
    unidade(2, 309, 'João Batista Ferreira', 'reuniao_qualificada', 45),
    unidade(3, 311, 'Sebastião Pereira Nunes', 'reuniao_qualificada', 45),
    unidade(3, 314, 'Rosângela Pereira Costa', 'reuniao_qualificada', 45),
  ],
};
const RAFAEL = {
  user: { id: 12, name: 'Rafael Cardoso Lemos' },
  papel: 'closer',
  meta: 18,
  rampa: false,
  contagem: 3,
  subtotal: 540,
  bonus: 0,
  degraus: 0,
  garantia_aplicada: false,
  total: 540,
  unidades: [
    unidade(1, 290, 'Ivone Schmitz da Silva', 'contrato_limpo', 180),
    unidade(2, 301, 'Maria de Lourdes Souza', 'contrato_limpo', 180),
    unidade(3, 276, 'Valdir Coelho Martins', 'contrato_limpo', 180),
  ],
};
const BRUNA = {
  user: { id: 13, name: 'Bruna Fernandes Kock' },
  papel: 'sdr',
  meta: 25,
  rampa: true,
  contagem: 0,
  subtotal: 0,
  bonus: 0,
  degraus: 0,
  garantia_aplicada: true,
  total: 800,
  unidades: [],
};

const RADAR = {
  summary: {
    bleeding_monthly: 11240,
    bleeding_count: 8,
    at_risk_90d_monthly: 23700,
    at_risk_90d_count: 5,
  },
  items: [
    {
      lead_id: 1,
      name: 'Osmar Vieira da Cunha',
      benefit_type_name: 'Auxílio-acidente (B94)',
      dcb_em: '2020-11-10',
      stage_name: 'Perdido',
      is_lost: true,
      monthly_value: 2106,
      lost_installments: 9,
      months_to_cliff: 0,
      pct_consumed: 1,
      consent_marketing: true,
    },
    {
      lead_id: 2,
      name: 'Maria de Lourdes Souza',
      benefit_type_name: 'Auxílio por incapacidade (B31)',
      dcb_em: '2021-03-03',
      stage_name: 'Qualificado',
      is_lost: false,
      monthly_value: 1412,
      lost_installments: 4,
      months_to_cliff: 0,
      pct_consumed: 1,
      consent_marketing: true,
    },
    {
      lead_id: 3,
      name: 'Sebastião Pereira Nunes',
      benefit_type_name: null,
      dcb_em: '2021-01-20',
      stage_name: 'Reunião agendada',
      is_lost: false,
      monthly_value: null,
      lost_installments: 2,
      months_to_cliff: 0,
      pct_consumed: 1,
      consent_marketing: false,
    },
    {
      lead_id: 4,
      name: 'João Batista Ferreira',
      benefit_type_name: 'Auxílio-acidente (B94)',
      dcb_em: '2021-09-15',
      stage_name: 'Novo',
      is_lost: false,
      monthly_value: 1830,
      lost_installments: 0,
      months_to_cliff: 1,
      pct_consumed: 0.966,
      consent_marketing: true,
    },
    {
      lead_id: 5,
      name: 'Terezinha Medeiros Rocha',
      benefit_type_name: 'Auxílio por incapacidade (B31)',
      dcb_em: '2021-12-02',
      stage_name: 'Contato feito',
      is_lost: false,
      monthly_value: 1518,
      lost_installments: 0,
      months_to_cliff: 3,
      pct_consumed: 0.62,
      consent_marketing: false,
    },
  ],
};

const POS_VENDA = {
  pendentes: [
    {
      id: 21,
      name: 'Valdir Coelho Martins',
      dias: 19,
      docs_received: 2,
      docs_total: 6,
      conversation_id: 801,
    },
    {
      id: 22,
      name: 'Ivone Schmitz da Silva',
      dias: 9,
      docs_received: 4,
      docs_total: 5,
      conversation_id: 802,
    },
    {
      id: 23,
      name: 'Rosângela Pereira Costa',
      dias: 3,
      docs_received: 0,
      docs_total: 4,
      conversation_id: null,
    },
  ],
  concluidos: [
    { id: 24, name: 'Antônio Carlos Westrup', drive_concluido: true },
    { id: 25, name: 'Neusa Maria Bonetti', drive_concluido: false },
  ],
};

const API = {
  ramon_extrato: { pessoas: [LARISSA, RAFAEL, BRUNA] },
  ramon_prescription_radar: RADAR,
  ramon_pos_venda: POS_VENDA,
};

let respostas = API;
let falhar = false;
const responder = async url => {
  if (falhar) throw new Error('offline');
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

const rota = reactive({ params: { accountId: 1 }, query: {} });
provide(routeLocationKey, rota);
provide(routerKey, { push: () => {}, resolve: () => ({ href: '#' }) });

const store = useStore();
store.registerModule('route', { state: { params: { accountId: 1 } } });
const papel = role =>
  store.commit('SET_CURRENT_USER', {
    id: role === 'administrator' ? 1 : 11,
    accounts: [{ id: 1, role }],
  });

const clicar = texto =>
  [...document.querySelectorAll('button')]
    .find(b => b.textContent.includes(texto))
    ?.click();
const depois = (ms, fn) => () => setTimeout(fn, ms);

const gestor = () => papel('administrator');
// C1: mês fechado (guardado, com fechado_em) e desconto de contrato pago num
// mês fechado e cancelado depois (+ bônus desfeito, no Closer).
const fechado = () => {
  papel('administrator');
  const fechadoEm = '2026-11-04T03:20:00Z';
  const desconto = (lead_id, lead_nome, evento, valor) => ({
    ...unidade(2, lead_id, lead_nome, evento, valor),
    competencia_origem: '2026-09-01',
  });
  respostas = {
    ...API,
    ramon_extrato: {
      pessoas: [
        {
          ...LARISSA,
          fechado_em: fechadoEm,
          unidades: [
            ...LARISSA.unidades,
            desconto(250, 'Neusa Maria Bonetti', 'desconto', -10),
          ],
          descontos: -10,
          total: 410,
        },
        {
          ...RAFAEL,
          fechado_em: fechadoEm,
          unidades: [
            ...RAFAEL.unidades,
            desconto(250, 'Neusa Maria Bonetti', 'desconto', -22),
            desconto(250, 'Neusa Maria Bonetti', 'desconto_bonus', -150),
          ],
          descontos: -172,
          total: 368,
        },
      ],
    },
  };
};
const agente = () => {
  papel('agent');
  respostas = { ...API, ramon_extrato: { pessoas: [LARISSA] } };
};
const vazioGestor = () => {
  papel('administrator');
  respostas = { ...API, ramon_extrato: { pessoas: [] } };
};
const erro = () => {
  papel('administrator');
  falhar = true;
};
const radarVazio = () => {
  respostas = {
    ...API,
    ramon_prescription_radar: {
      summary: {
        bleeding_monthly: 0,
        bleeding_count: 0,
        at_risk_90d_monthly: 0,
        at_risk_90d_count: 0,
      },
      items: [],
    },
  };
};
const radarModal = depois(1500, () => clicar('Criar campanha de resgate'));
const posVendaAberto = depois(1500, () => clicar('Concluídos'));
const posVendaVazio = () => {
  respostas = {
    ...API,
    ramon_pos_venda: { pendentes: [], concluidos: POS_VENDA.concluidos },
  };
};
</script>

<template>
  <Story title="Ramon/Extrato, Radar e Pós-venda" :layout="{ type: 'single' }">
    <Variant title="Extrato gestor" :init-state="gestor">
      <div class="h-screen"><Extrato /></div>
    </Variant>
    <Variant title="Extrato agente" :init-state="agente">
      <div class="h-screen"><Extrato /></div>
    </Variant>
    <Variant title="Extrato vazio" :init-state="vazioGestor">
      <div class="h-screen"><Extrato /></div>
    </Variant>
    <Variant title="Extrato fechado" :init-state="fechado">
      <div class="h-screen"><Extrato /></div>
    </Variant>
    <Variant title="Extrato erro" :init-state="erro">
      <div class="h-screen"><Extrato /></div>
    </Variant>
    <Variant title="Radar">
      <div class="h-screen"><RadarPrescricao /></div>
    </Variant>
    <Variant title="Radar campanha" :init-state="radarModal">
      <div class="h-screen"><RadarPrescricao /></div>
    </Variant>
    <Variant title="Radar vazio" :init-state="radarVazio">
      <div class="h-screen"><RadarPrescricao /></div>
    </Variant>
    <Variant title="Radar erro" :init-state="erro">
      <div class="h-screen"><RadarPrescricao /></div>
    </Variant>
    <Variant title="Pos-venda" :init-state="posVendaAberto">
      <div class="h-screen"><PosVenda /></div>
    </Variant>
    <Variant title="Pos-venda vazio" :init-state="posVendaVazio">
      <div class="h-screen"><PosVenda /></div>
    </Variant>
    <Variant title="Pos-venda erro" :init-state="erro">
      <div class="h-screen"><PosVenda /></div>
    </Variant>
  </Story>
</template>
