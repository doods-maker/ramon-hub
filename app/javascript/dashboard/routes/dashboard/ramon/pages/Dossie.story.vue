<script setup>
// Story do Dossiê (ficha completa do lead) + Linha da Vida (aprovação visual
// por print, claro/escuro). Sem rede: window.axios responde por URL com dados
// fictícios; sem router: a rota de cada variante entra por provide.
import { h, provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Dossie from './Dossie.vue';
import LinhaDaVida from './LinhaDaVida.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();
const diasAFrente = n => diasAtras(-n).slice(0, 10);
const anosAtras = n => diasAtras(n * 365).slice(0, 10);

const ETAPAS = [
  { id: 1, name: 'Novo', color: '#64748b' },
  { id: 2, name: 'Qualificação', color: '#0ea5e9' },
  { id: 3, name: 'Reunião', color: '#f59e0b' },
  { id: 4, name: 'Assinatura', color: '#3b82f6' },
  { id: 5, name: 'Ganho', color: '#22c55e', is_won: true },
  { id: 6, name: 'Perdido', color: '#ef4444', is_lost: true },
];
// esteira com a etapa atual marcada e as datas de entrada até ela
const esteira = (atualId, entradas) =>
  ETAPAS.map((etapa, i) => ({
    is_won: false,
    is_lost: false,
    ...etapa,
    position: i + 1,
    current: etapa.id === atualId,
    entered_at: entradas[i] ?? null,
  }));

const DOSSIE = {
  pessoa: {
    lead_id: 7,
    lead_name: 'João Carlos Pereira',
    stage_name: 'Reunião',
    stage_color: '#f59e0b',
    value: 38400,
    conversation_id: 101,
    probability: 60,
    stage_entered_at: diasAtras(2),
    valor_estimado_origem: 'auto',
    thesis_name: 'Auxílio-acidente',
    contact_id: 9,
    contact_name: 'João Carlos Pereira',
    phone_number: '+5548991234567',
    idade: 58,
    cidade: 'Tubarão',
    consent_marketing: true,
  },
  origem: {
    source: 'lp-auxilio-acidente',
    channel: 'meta_ads',
    channel_label: 'Meta Ads',
    utm: { utm_campaign: 'aux-acidente-sc', utm_content: 'reels-mao' },
    indicacao: false,
  },
  triagem: {
    id: 3,
    status: 'done',
    viability: 'alta',
    result:
      'Acidente de trajeto em 2022 com fratura no punho direito; CAT emitida. Sequela reduz a capacidade para a função de pedreiro — indício forte de auxílio-acidente.',
  },
  tese: {
    id: 1,
    name: 'Auxílio-acidente',
    honorario_text: '30% dos atrasados + 3 mensalidades',
    objecoes: [
      {
        title: 'Vou perder o emprego?',
        content:
          'Não. O auxílio-acidente é indenização e pode ser recebido junto com o salário.',
      },
      {
        title: 'É caro?',
        content:
          'Você só paga se o benefício sair, e o valor fica combinado por escrito antes.',
      },
    ],
  },
  esteira: esteira(3, [diasAtras(12), diasAtras(9), diasAtras(2)]),
  docs: {
    received: 2,
    total: 4,
    itens: [
      { id: 1, title: 'RG e CPF', status: 'recebido' },
      { id: 2, title: 'CAT (Comunicação de Acidente)', status: 'recebido' },
      { id: 3, title: 'CNIS atualizado', status: 'solicitado' },
      { id: 4, title: 'Laudo do ortopedista', status: 'pendente' },
    ],
  },
  calculos: [
    {
      id: 1,
      tipo: 'painel',
      segurado_nome: 'João Carlos Pereira',
      created_at: diasAtras(3),
    },
    {
      id: 2,
      tipo: 'honorario',
      segurado_nome: 'João Carlos Pereira',
      created_at: diasAtras(3),
    },
  ],
  reunioes: [
    {
      id: 1,
      titulo: 'Reunião de fechamento — João',
      status: 'pronta',
      created_at: diasAtras(1),
    },
  ],
  timeline: [
    {
      type: 'note',
      body: 'Vai trazer o laudo do ortopedista na reunião de quinta.',
      author_name: 'Eduardo Schlata',
      created_at: diasAtras(1),
    },
    {
      type: 'activity',
      kind: 'reuniao_registrada',
      to_value: 'Reunião de fechamento — João',
      author_name: 'Eduardo Schlata',
      created_at: diasAtras(1.2),
    },
    {
      type: 'activity',
      kind: 'stage_changed',
      from_value: 'Qualificação',
      to_value: 'Reunião',
      author_name: 'Gabriela Matos',
      created_at: diasAtras(2),
    },
    {
      type: 'activity',
      kind: 'meeting_scheduled',
      to_value: null,
      author_name: null,
      created_at: diasAtras(2.1),
    },
    {
      type: 'activity',
      kind: 'value_changed',
      from_value: null,
      to_value: '38400.0',
      author_name: 'Gabriela Matos',
      created_at: diasAtras(3),
    },
    {
      type: 'activity',
      kind: 'stage_changed',
      from_value: 'Novo',
      to_value: 'Qualificação',
      author_name: 'Gabriela Matos',
      created_at: diasAtras(9),
    },
    {
      type: 'activity',
      kind: 'created',
      author_name: null,
      created_at: diasAtras(12),
    },
  ],
  pendencias: {
    tasks: [
      {
        id: 1,
        title: 'Reunião de fechamento',
        kind: 'meeting',
        due_at: diasAtras(-2),
      },
      { id: 2, title: 'Cobrar CNIS', kind: 'task', due_at: diasAtras(-3) },
    ],
    docs_missing: [
      { title: 'CNIS atualizado', status: 'solicitado' },
      { title: 'Laudo do ortopedista', status: 'pendente' },
    ],
  },
};

const DOSSIE_GANHO = {
  ...DOSSIE,
  pessoa: {
    ...DOSSIE.pessoa,
    lead_id: 8,
    lead_name: 'Maria Aparecida Souza',
    contact_name: 'Maria Aparecida Souza',
    phone_number: '+5548998765432',
    idade: 61,
    cidade: 'Laguna',
    stage_name: 'Ganho',
    stage_color: '#22c55e',
    probability: 100,
    value: 52300,
    valor_estimado_origem: null,
    consent_marketing: false,
  },
  origem: {
    source: 'indicação do filho (cliente 2023)',
    channel: 'indicacao',
    channel_label: 'Indicação',
    utm: {},
    indicacao: true,
  },
  esteira: esteira(5, [
    diasAtras(40),
    diasAtras(35),
    diasAtras(20),
    diasAtras(8),
    diasAtras(1),
  ]),
  docs: {
    received: 4,
    total: 4,
    itens: DOSSIE.docs.itens.map(item => ({ ...item, status: 'recebido' })),
  },
  timeline: [
    {
      type: 'activity',
      kind: 'zapsign_signed',
      author_name: null,
      created_at: diasAtras(1),
    },
    {
      type: 'activity',
      kind: 'stage_changed',
      from_value: 'Assinatura',
      to_value: 'Ganho',
      author_name: 'Eduardo Schlata',
      created_at: diasAtras(1),
    },
    {
      type: 'note',
      body: 'Contrato assinado; passar para o jurídico com o dossiê.',
      author_name: 'Eduardo Schlata',
      created_at: diasAtras(1),
    },
    {
      type: 'activity',
      kind: 'stage_changed',
      from_value: 'Reunião',
      to_value: 'Assinatura',
      author_name: 'Eduardo Schlata',
      created_at: diasAtras(8),
    },
  ],
  pendencias: { tasks: [], docs_missing: [] },
};

const DOSSIE_NOVO = {
  pessoa: {
    lead_id: 10,
    lead_name: 'Ana Lúcia Ramos',
    stage_name: 'Novo',
    stage_color: '#64748b',
    value: null,
    conversation_id: 110,
    probability: null,
    thesis_name: null,
    contact_id: 12,
    contact_name: 'Ana Lúcia Ramos',
    phone_number: '+5547996543210',
    idade: null,
    cidade: null,
    consent_marketing: false,
  },
  origem: {
    source: null,
    channel: 'whatsapp',
    channel_label: 'WhatsApp',
    utm: {},
    indicacao: false,
  },
  triagem: null,
  tese: null,
  esteira: esteira(1, [diasAtras(0)]),
  docs: { received: 0, total: 0, itens: [] },
  calculos: [],
  reunioes: [],
  timeline: [
    {
      type: 'activity',
      kind: 'created',
      author_name: null,
      created_at: diasAtras(0.1),
    },
  ],
  pendencias: { tasks: [], docs_missing: [] },
};

const LINHA = {
  contact: {
    id: 9,
    name: 'João Carlos Pereira',
    phone_number: '+5548991234567',
    email: 'joao.pereira@exemplo.com.br',
    cpf: '52998224725',
    data_nascimento: '1968-05-14',
    sexo: 'M',
  },
  leads: [
    {
      id: 3,
      name: 'João — BPC da mãe (Dona Ilda)',
      created_at: anosAtras(5),
      lost_at: anosAtras(4),
      is_won: false,
      is_lost: true,
      stage_name: 'Perdido',
      stage_color: '#ef4444',
      benefit_type_name: 'BPC/LOAS',
      value: 9000,
      lost_reason: 'Renda acima do limite',
    },
    {
      id: 5,
      name: 'João — Auxílio-doença 2023',
      created_at: anosAtras(3),
      won_at: anosAtras(2.6),
      is_won: true,
      is_lost: false,
      stage_name: 'Ganho',
      stage_color: '#22c55e',
      benefit_type_name: 'Auxílio-doença (B31)',
      value: 14200,
    },
    {
      id: 7,
      name: 'João — Auxílio-acidente',
      created_at: diasAtras(12),
      is_won: false,
      is_lost: false,
      stage_name: 'Reunião',
      stage_color: '#f59e0b',
      benefit_type_name: 'Auxílio-acidente (B94)',
      thesis_name: 'Auxílio-acidente',
      value: 38400,
      dcb_em: anosAtras(3.4),
      conversation_id: 101,
    },
    {
      id: 11,
      name: 'João — Revisão da vida toda',
      created_at: diasAtras(4),
      is_won: false,
      is_lost: false,
      stage_name: 'Qualificação',
      stage_color: '#0ea5e9',
      benefit_type_name: 'Aposentadoria por idade',
      dcb_em: diasAFrente(75),
      conversation_id: 102,
    },
  ],
  marcos: [
    {
      key: 'aposentadoria_idade_rural',
      sexo: 'M',
      idade: 60,
      data: '2028-05-14',
      atingido: false,
    },
    {
      key: 'aposentadoria_idade_urbana',
      sexo: 'M',
      idade: 65,
      data: '2033-05-14',
      atingido: false,
    },
    {
      key: 'bpc_loas_idoso',
      sexo: 'M',
      idade: 65,
      data: '2033-05-14',
      atingido: false,
    },
  ],
};

const LINHA_VAZIA = {
  contact: {
    id: 13,
    name: 'Ana Lúcia Ramos',
    phone_number: '+5547996543210',
    cpf: null,
    data_nascimento: null,
    sexo: null,
  },
  leads: [],
  marcos: [],
};

const API = {
  'leads/7/dossie': DOSSIE,
  'leads/8/dossie': DOSSIE_GANHO,
  'leads/10/dossie': DOSSIE_NOVO,
  'contacts/9/linha_da_vida': LINHA,
  'contacts/13/linha_da_vida': LINHA_VAZIA,
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
store.registerModule('route', { state: { params: { accountId: 1 } } });

// as páginas leem a rota com useRoute(): cada variante entrega a sua
const ComRota = {
  props: { params: { type: Object, required: true } },
  setup(props, { slots }) {
    provide(
      routeLocationKey,
      reactive({ params: { accountId: 1, ...props.params }, query: {} })
    );
    provide(routerKey, { push: () => {}, resolve: () => ({ href: '#' }) });
    return () => h('div', { class: 'h-screen' }, slots.default?.());
  },
};
</script>

<template>
  <Story
    title="Ramon/Dossiê e Linha da Vida"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Dossie">
      <ComRota :params="{ leadId: 7 }"><Dossie /></ComRota>
    </Variant>
    <Variant title="Dossie ganho">
      <ComRota :params="{ leadId: 8 }"><Dossie /></ComRota>
    </Variant>
    <Variant title="Dossie novo">
      <ComRota :params="{ leadId: 10 }"><Dossie /></ComRota>
    </Variant>
    <Variant title="Linha da Vida">
      <ComRota :params="{ contactId: 9 }"><LinhaDaVida /></ComRota>
    </Variant>
    <Variant title="Linha da Vida vazia">
      <ComRota :params="{ contactId: 13 }"><LinhaDaVida /></ComRota>
    </Variant>
    <Variant title="Linha da Vida busca">
      <ComRota :params="{}"><LinhaDaVida /></ComRota>
    </Variant>
  </Story>
</template>
