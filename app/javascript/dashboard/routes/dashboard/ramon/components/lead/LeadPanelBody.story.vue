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
    label: 'fase-reuniao-agendada',
    color: '#f59e0b',
    position: 3,
    probability: 50,
  },
  {
    id: 4,
    name: 'Reunião realizada',
    label: 'fase-reuniao-realizada',
    color: '#06b6d4',
    position: 4,
    probability: 60,
  },
  { id: 5, name: 'Negociação', color: '#14b8a6', position: 5, probability: 70 },
  {
    id: 6,
    name: 'Fechado',
    color: '#22c55e',
    position: 6,
    probability: 100,
    is_won: true,
  },
  {
    id: 7,
    name: 'Perdido',
    color: '#ef4444',
    position: 7,
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

// Reunião agendada que já passou (Closer ainda não registrou o resultado)
const LEAD_REUNIAO = { ...LEAD, id: 44 };
// Contrato já gerado no ZapSign (link pronto, 2 campos saíram em branco)
const LEAD_CONTRATO_GERADO = {
  ...LEAD,
  custom_attributes: {
    ...LEAD.custom_attributes,
    zapsign: {
      doc_token: 'doc-1',
      sign_url: 'https://app.zapsign.com.br/verificar/doc-1',
      faltando: ['{{número}}', '{{bairro}}'],
      template_name: 'Contrato + procuração — auxílio-acidente',
      criado_em: diasAtras(1),
    },
  },
};

// Assinado (webhook do ZapSign) e recusado pelo cliente
const LEAD_CONTRATO_ASSINADO = {
  ...LEAD_CONTRATO_GERADO,
  custom_attributes: {
    ...LEAD.custom_attributes,
    zapsign: {
      ...LEAD_CONTRATO_GERADO.custom_attributes.zapsign,
      status: 'signed',
      assinado_em: diasAtras(0),
    },
  },
};
const LEAD_CONTRATO_RECUSADO = {
  ...LEAD_CONTRATO_GERADO,
  custom_attributes: {
    ...LEAD.custom_attributes,
    zapsign: {
      ...LEAD_CONTRATO_GERADO.custom_attributes.zapsign,
      status: 'refused',
      recusado_em: diasAtras(0),
    },
  },
};

// Em Qualificação: ainda sem contrato em jogo (painel com 4 ícones)
const LEAD_QUALIFICACAO = { ...LEAD, id: 45, lead_stage_id: 2 };

// Reunião realizada: fase de contrato (painel com 5 ícones)
const LEAD_CONTRATO = {
  ...LEAD,
  id: 46,
  lead_stage_id: 4,
  stage_entered_at: diasAtras(1),
};

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
  'leads/44/tasks': {
    payload: [
      {
        id: 2,
        lead_id: 44,
        title: 'Reunião Cal.com: Primeiro Atendimento',
        kind: 'meeting',
        due_at: diasAtras(1),
      },
    ],
  },
  'leads/44/notes': {
    payload: [
      {
        id: 4,
        author_name: null,
        body: 'RASCUNHO (revisar antes de enviar) — confirmação de reunião:\n"Oi João! Nossa conversa está confirmada pra sexta, 02/10 às 14:00. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."',
        created_at: diasAtras(4),
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
  // prévia do contrato: endereço só com cidade/UF — rua/número/bairro em branco
  'leads/42/zapsign/preview': {
    faltando: ['{{rua}}', '{{número}}', '{{bairro}}'],
    dados: {
      cidade: 'Tubarão',
      uf: 'SC',
      estado_civil: 'casado(a)',
      profissao: 'montador industrial',
      email: 'joao.pereira@email.com',
    },
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
// Resumo + cliques em sequência (abre formulário/seção para o print)
const clicando =
  (...testIds) =>
  () => {
    localStorage.setItem('ramon_lead_panel_tab', 'resumo');
    setTimeout(async () => {
      // eslint-disable-next-line no-restricted-syntax
      for (const id of testIds) {
        document.querySelector(`[data-testid="${id}"]`)?.click();
        // eslint-disable-next-line no-await-in-loop
        await new Promise(r => {
          setTimeout(r, 300);
        });
      }
    }, 800);
    return {};
  };
// Estados internos do cartão (janela aberta) só por clique: clica em ordem.
const comAbaEClique =
  (tab, ...testids) =>
  () => {
    testids.forEach((id, i) =>
      setTimeout(
        () => document.querySelector(`[data-testid="${id}"]`)?.click(),
        1000 + i * 500
      )
    );
    return comAba(tab)();
  };
// Resumo rolado até o fim (depois que notas/cartões carregam)
const rolandoAoFim = () => {
  localStorage.setItem('ramon_lead_panel_tab', 'resumo');
  setTimeout(() => {
    const corpo = document.querySelector('[data-testid="lead-panel-corpo"]');
    if (corpo) corpo.scrollTop = corpo.scrollHeight;
  }, 2500);
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
    <Variant title="Tarefa" :init-state="clicando('panel-add-task')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant
      title="TarefaReuniao"
      :init-state="clicando('panel-add-task', 'panel-task-kind-meeting')"
    >
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant
      title="EditarTudo"
      :init-state="clicando('contact-data-toggle', 'lead-edit-all-toggle')"
    >
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="ReuniaoPassada" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_REUNIAO"
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
    <Variant title="Contrato" :init-state="comAba('contrato')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Contrato gerado" :init-state="comAba('contrato')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO_GERADO"
    <Variant title="Qualificacao" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_QUALIFICACAO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant
      title="Contrato gerar de novo"
      :init-state="
        comAbaEClique('contrato', 'zapsign-regenerate', 'zapsign-generate')
      "
    >
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO_GERADO"
    <Variant title="FaseContrato" :init-state="comAba('resumo')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Contrato assinado" :init-state="comAba('contrato')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO_ASSINADO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Contrato recusado" :init-state="comAba('contrato')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD_CONTRATO_RECUSADO"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <Variant title="Historico" :init-state="comAba('historico')">
    <Variant title="Scripts" :init-state="comAba('playbook')">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <!-- fim do Resumo: link "Histórico completo na ficha" -->
    <Variant title="FimResumo" :init-state="rolandoAoFim">
      <div class="h-screen w-[400px] flex bg-n-background">
        <LeadPanelBody
          :lead="LEAD"
          context="conversation"
          :conversation-id="101"
        />
      </div>
    </Variant>
    <!-- Simular largo: painel à direita de uma página 1440px (conversa fake) -->
    <Variant
      title="SimuladorLargo"
      :init-state="clicando('lead-nav-simulador')"
    >
      <div class="h-screen w-full flex bg-n-background">
        <div class="flex-1 flex flex-col gap-3 p-6 border-r border-n-weak">
          <div
            v-for="n in 6"
            :key="n"
            class="h-10 rounded-xl bg-n-alpha-2"
            :class="n % 2 ? 'w-2/5' : 'w-1/3 self-end'"
          />
        </div>
        <div class="w-[400px] flex">
          <LeadPanelBody
            :lead="LEAD"
            context="conversation"
            :conversation-id="101"
          />
        </div>
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
