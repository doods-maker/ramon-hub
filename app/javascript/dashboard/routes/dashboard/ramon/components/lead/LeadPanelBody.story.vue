<script setup>
// Story do painel do lead (aprovação visual por print, claro/escuro).
// Sem rede: window.axios responde com dados de exemplo por URL.
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import LeadPanelBody from './LeadPanelBody.vue';
import LeadFields from './LeadFields.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const diasAtras = n => new Date(Date.now() - n * 86400000).toISOString();
const emDias = n => new Date(Date.now() + n * 86400000).toISOString();

const STAGES = [
  { id: 1, name: 'Novo', color: '#3b82f6', position: 1, probability: 10 },
  {
    id: 2,
    name: 'Qualificação',
    color: '#8b5cf6',
    position: 2,
    probability: 25,
  },
  {
    id: 3,
    name: 'Reunião agendada',
    color: '#f59e0b',
    position: 3,
    probability: 50,
  },
  { id: 4, name: 'Negociação', color: '#14b8a6', position: 4, probability: 70 },
  {
    id: 5,
    name: 'Fechado',
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

const THESIS = {
  id: 1,
  name: 'Auxílio-acidente',
  active: true,
  position: 1,
  items: [
    { id: 11, section: 'documento', title: 'RG e CPF' },
    { id: 12, section: 'documento', title: 'Comprovante de residência' },
    { id: 13, section: 'documento', title: 'CTPS' },
    { id: 14, section: 'documento', title: 'Laudo médico / CAT' },
    { id: 15, section: 'documento', title: 'Carta de concessão do B91' },
    {
      id: 21,
      section: 'qualificacao',
      title: 'Teve afastamento pelo INSS (B31/B91)?',
    },
    {
      id: 22,
      section: 'qualificacao',
      title: 'Ficou com sequela que reduz a capacidade?',
    },
    {
      id: 23,
      section: 'qualificacao',
      title: 'Tinha carteira assinada no acidente?',
    },
    { id: 24, section: 'qualificacao', title: 'Recebe algum benefício hoje?' },
    {
      id: 31,
      section: 'apresentacao',
      title: 'Abertura',
      content:
        'Oi! Aqui é do escritório Ramon Antonio. Vi que você teve um acidente — posso te fazer umas perguntas rápidas?',
    },
    {
      id: 32,
      section: 'objecao',
      title: 'Já tentei e o INSS negou',
      content:
        'Muita gente ouve "não" no INSS e depois consegue na Justiça. O que conta é a sequela e o laudo.',
    },
  ],
};

const LEAD = {
  id: 42,
  name: 'João Carlos Pereira',
  lead_stage_id: 3,
  stage_entered_at: diasAtras(4),
  value: 18500,
  thesis_id: 1,
  thesis_name: 'Auxílio-acidente',
  benefit_type_name: 'B94',
  dcb_em: '2021-12-10',
  benefit_monthly_value: 1412,
  channel: 'whatsapp',
  source: 'Meta Ads',
  contact_id: 7,
  contact_name: 'João Carlos Pereira',
  contact_phone: '+55 48 99812-3456',
  contact_cpf: '12345678909',
  contact_email: 'joao.pereira@email.com',
  contact_data_nascimento: '1979-04-22',
  contact_sexo: 'M',
  benefit_type_id: 1,
  sdr_name: 'Eduardo',
  closer_name: 'Dr. Ramon',
  docs_total: 5,
  docs_received: 3,
  conversation_id: 101,
  follow_up_count: 1,
  cnis_resumo: {
    filename: 'CNIS-joao-pereira.pdf',
    competencias: 214,
    vinculos: 6,
  },
  stalled: false,
  custom_attributes: {
    valor_estimado: { origem: 'auto' },
    doc_status: {
      11: 'recebido',
      12: 'recebido',
      13: 'recebido',
      14: 'solicitado',
    },
    qualificacao_status: { 21: 'ok', 22: 'ok', 23: 'falta' },
    ultima_simulacao: {
      mensal: 706,
      atrasados: 25416,
      honorario_valor: 9742.8,
      tese: 'Auxílio-acidente',
      em: diasAtras(3),
      parametros: {
        der: '2021-12-11',
        salario: '2824',
        beneficio: 'acidente',
        origem: 'acidentaria',
        acrescimo_25: false,
        usar_cnis: true,
      },
    },
  },
};

// Lead parado (cartão "Risco de esfriar") com rascunho de retomada nas notas
const LEAD_PARADO = {
  ...LEAD,
  id: 43,
  stalled: true,
  stage_entered_at: diasAtras(12),
  follow_up_count: 1,
};

// DCB há mais de 5 anos: parcelas já prescrevendo (chip ruby no cabeçalho)
const LEAD_PRESCREVENDO = { ...LEAD, dcb_em: '2020-06-10' };

const API = {
  lead_config: {
    stages: STAGES,
    channels: [{ key: 'whatsapp', label: 'WhatsApp' }],
    lost_reasons: [{ id: 1, name: 'Sem documentos' }],
    benefit_types: [{ id: 1, name: 'B94' }],
    priorities: [{ id: 1, name: 'Alta' }],
  },
  theses: [THESIS],
  'theses/1': THESIS,
  'leads/42/tasks': {
    payload: [
      {
        id: 1,
        lead_id: 42,
        title: 'Ligar para confirmar a reunião',
        kind: 'follow_up',
        due_at: emDias(1),
      },
    ],
  },
  'leads/42/notes': {
    payload: [
      {
        id: 1,
        author_name: 'Eduardo',
        body: 'Cliente mandou a CTPS pelo WhatsApp. Falta o laudo.',
        created_at: diasAtras(1),
      },
    ],
  },
  'leads/43/notes': {
    payload: [
      {
        id: 2,
        author_name: 'Eduardo',
        body: 'Ligou dizendo que ia buscar o laudo no posto.',
        created_at: diasAtras(13),
      },
      {
        id: 3,
        author_name: null,
        body: 'RASCUNHO (revisar antes de enviar) — retomada nº 2:\nOi João, tudo bem? Conseguiu pegar o laudo no posto? Se quiser, me manda uma foto dele por aqui que eu já confiro pra você.',
        created_at: diasAtras(0),
      },
    ],
  },
  'leads/42/activities': {
    payload: [
      { id: 1, kind: 'created', created_at: diasAtras(9) },
      {
        id: 2,
        kind: 'stage_changed',
        to_value: 'Qualificação',
        author_name: 'Eduardo',
        created_at: diasAtras(7),
      },
      {
        id: 3,
        kind: 'value_changed',
        to_value: '18500',
        created_at: diasAtras(6),
      },
      {
        id: 4,
        kind: 'stage_changed',
        to_value: 'Reunião agendada',
        author_name: 'Eduardo',
        created_at: diasAtras(4),
      },
    ],
  },
  'leads/zapsign_templates': [
    { token: 'a', name: 'Contrato + procuração — auxílio-acidente' },
  ],
};

const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
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
store.commit(types.SET_ALL_CONVERSATION, [
  { id: 101, status: 'open', messages: [], meta: {}, custom_attributes: {} },
]);
store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: 101 });
store.dispatch('leadConfig/get');
store.dispatch('theses/get');

const comAba = tab => () => {
  localStorage.setItem('ramon_lead_panel_tab', tab);
  return {};
};
</script>

<template>
  <Story
    title="Ramon/Painel do lead"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Resumo" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Prescrevendo" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_PRESCREVENDO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Retomada" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_PARADO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Documentos" :init-state="comAba('documentos')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Simulador" :init-state="comAba('simulador')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Contrato" :init-state="comAba('contrato')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Historico" :init-state="comAba('historico')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <!-- "Dados do contato" → "Editar todos os campos" aberto -->
    <Variant title="Campos">
      <div class="w-[400px] p-3 bg-n-background">
        <LeadFields :lead="LEAD" />
      </div>
    </Variant>
  </Story>
</template>
