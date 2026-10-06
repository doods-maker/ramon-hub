<script setup>
// Story das telas NATIVAS de Conversas (lista da caixa de entrada) e Contatos
// (lista + detalhe), para aprovar o padrão visual por print (claro/escuro).
// Monta os componentes reais (ChatList, ContactsIndex, ContactManageView):
// window.axios responde com dados FICTÍCIOS por URL e a rota entra por provide.
import { getCurrentInstance, provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { createPinia } from 'pinia';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import WootUiKit from 'dashboard/components';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue';
import ChatList from 'dashboard/components/ChatList.vue';
import ContactsIndex from 'dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue';
import ContactManageView from 'dashboard/routes/dashboard/contacts/pages/ContactManageView.vue';

// Globais que o app registra no entrypoint (woot-tabs, woot-label,
// fluent-icon, pinia).
const { app } = getCurrentInstance().appContext;
if (!app.component('woot-tabs')) app.use(WootUiKit);
if (!app.component('fluent-icon')) app.component('fluent-icon', FluentIcon);
if (!app.config.globalProperties.$pinia) app.use(createPinia());

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const agora = Math.floor(Date.now() / 1000);
const MIN = 60;

const INBOXES = [
  {
    id: 1,
    name: 'Comercial',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
    phone_number: '+5548900000001',
  },
  {
    id: 2,
    name: 'Escritório',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
    phone_number: '+5548900000002',
  },
];

const LABELS = [
  { id: 1, title: 'auxilio-acidente', color: '#2563eb', description: '' },
  { id: 2, title: 'bpc-loas', color: '#16a34a', description: '' },
  { id: 3, title: 'urgente', color: '#dc2626', description: '' },
  { id: 4, title: 'documentos', color: '#d97706', description: '' },
];

const pessoa = (id, name, extra = {}) => ({
  id,
  name,
  thumbnail: '',
  availability_status: 'offline',
  phone_number: `+55489000000${String(id).padStart(2, '0')}`,
  email: '',
  identifier: null,
  additional_attributes: { city: 'Tubarão', country: 'Brasil' },
  custom_attributes: {},
  created_at: agora - 30 * 86400,
  last_activity_at: agora - 2 * 3600,
  ...extra,
});

const AGENTE = { id: 1, name: 'Eduardo Schlata', thumbnail: '' };

const msg = (id, content, extra = {}) => ({
  id,
  content,
  message_type: 0,
  private: false,
  created_at: agora - 5 * MIN,
  content_type: 'text',
  attachments: undefined,
  ...extra,
});

const conversa = (id, sender, inboxId, minutos, extra = {}) => ({
  id,
  inbox_id: inboxId,
  status: 'open',
  unread_count: 0,
  timestamp: agora - minutos * MIN,
  created_at: agora - (minutos + 600) * MIN,
  labels: [],
  priority: null,
  messages: [],
  meta: {
    sender,
    assignee: AGENTE,
    channel: 'Channel::Whatsapp',
  },
  ...extra,
});

const CONVERSAS = [
  conversa(101, pessoa(1, 'Helena Duarte'), 1, 3, {
    unread_count: 2,
    labels: ['bpc-loas', 'documentos'],
    meta: {
      sender: pessoa(1, 'Helena Duarte'),
      assignee: AGENTE,
      channel: 'Channel::Whatsapp',
    },
    last_non_activity_message: msg(1, 'Qual documento ainda falta pra mandar?'),
  }),
  conversa(102, pessoa(2, 'Joaquim Farias'), 1, 18, {
    unread_count: 12,
    labels: ['auxilio-acidente', 'urgente'],
    priority: 'urgent',
    last_non_activity_message: msg(2, 'Tenho a CAT da empresa, serve?'),
  }),
  conversa(103, pessoa(3, 'Sônia Prado'), 2, 52, {
    labels: ['documentos'],
    last_non_activity_message: msg(
      3,
      'Cliente pediu pra explicar a carta do INSS antes da perícia.',
      { private: true, message_type: 1 }
    ),
  }),
  conversa(104, pessoa(4, 'Marcos Vieira'), 1, 140, {
    last_non_activity_message: msg(4, 'Obrigado, doutor! Fico no aguardo.', {
      message_type: 1,
    }),
  }),
  conversa(105, pessoa(5, '+55 48 9 9000-0042'), 2, 60 * 26, {
    meta: {
      sender: pessoa(5, '+55 48 9 9000-0042'),
      assignee: null,
      channel: 'Channel::Whatsapp',
    },
    last_non_activity_message: msg(
      5,
      'Boa tarde, vocês atendem aposentadoria?'
    ),
  }),
  conversa(106, pessoa(6, 'Lúcia Andrade'), 1, 60 * 24 * 3, {
    labels: ['auxilio-acidente'],
    last_non_activity_message: msg(6, '', {
      attachments: [{ file_type: 'audio' }],
    }),
  }),
];

const STATS = { mine_count: 5, unassigned_count: 1, all_count: 6 };

// Melhorias (06/10): o lead da conversa (linha "Etapa · Tese · Responsável"
// no card) e as etiquetas espelhadas fase-*/tese-*, que o card esconde.
const leadSlim = (id, stage, cor, tese, responsavel) => ({
  id,
  stage_name: stage,
  stage_color: cor,
  thesis_name: tese,
  sdr_name: 'Ana',
  closer_name: responsavel,
});
const LEADS = {
  101: leadSlim(1, 'Novo', '#64748b', 'BPC/LOAS', null),
  102: leadSlim(2, 'Em qualificação', '#0ea5e9', 'Auxílio-acidente', null),
  103: leadSlim(
    3,
    'Reunião marcada',
    '#8b5cf6',
    'Aposentadoria especial',
    'Bruno'
  ),
  104: leadSlim(
    4,
    'Aguardando assinatura',
    '#ec4899',
    'Auxílio-doença',
    'Bruno'
  ),
  106: leadSlim(6, 'Novo', '#64748b', null, null),
};
const CONVERSAS_COM_LEAD = CONVERSAS.map(c =>
  LEADS[c.id]
    ? {
        ...c,
        ramon_lead: LEADS[c.id],
        labels: [...c.labels, 'fase-novo', 'tese-bpc-loas'],
      }
    : c
);

const CONTATOS = [
  pessoa(1, 'Helena Duarte', { email: 'helena@exemplo.com.br' }),
  pessoa(2, 'Joaquim Farias'),
  pessoa(3, 'Sônia Prado', {
    email: 'sonia.prado@exemplo.com.br',
    additional_attributes: { company_name: 'Comércio Exemplo' },
  }),
  pessoa(4, 'Marcos Vieira', { email: 'marcos@exemplo.com.br' }),
  pessoa(6, 'Lúcia Andrade'),
];

const CONTATO_DETALHE = {
  ...CONTATOS[0],
  identifier: 'CLI-0001',
  blocked: false,
  cpf: '52998224725',
  data_nascimento: '1970-03-15',
};

// /linha_da_vida do contato com um lead aberto (bloco "Lead aberto" da ficha).
const LINHA_DA_VIDA = {
  contact: CONTATO_DETALHE,
  leads: [
    {
      id: 1,
      name: 'Helena Duarte',
      stage_name: 'Em qualificação',
      stage_color: '#0ea5e9',
      thesis_name: 'BPC/LOAS',
      sdr_name: 'Ana',
      closer_name: null,
      conversation_id: 101,
      is_won: false,
      is_lost: false,
    },
  ],
  marcos: [],
};

const ERRO = Symbol('erro');
const API = {
  conversations: {
    data: { meta: STATS, payload: CONVERSAS },
  },
  'conversations/meta': { meta: STATS },
  contacts: {
    payload: CONTATOS,
    meta: { count: CONTATOS.length, current_page: 1 },
  },
  'contacts/1': { payload: CONTATO_DETALHE },
  'contacts/1/labels': { payload: ['bpc-loas', 'documentos'] },
  'contacts/1/notes': [],
  'contacts/1/conversations': { payload: [] },
  custom_attribute_definitions: [],
  inboxes: { payload: INBOXES },
  labels: { payload: LABELS },
  campaigns: [],
};

let respostas = API;
const responder = async url => {
  const path = url
    .split('?')[0]
    .replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '')
    .replace(/^\//, '');
  if (respostas[path] === ERRO) throw new Error('rede');
  return { data: respostas[path] ?? { payload: [] } };
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
  accounts: [
    {
      id: 1,
      role: 'administrator',
      permissions: ['administrator'],
      active_at: new Date().toISOString(),
    },
  ],
  ui_settings: { conversation_display_type: 'condensed' },
});
store.commit(`inboxes/${types.SET_INBOXES}`, INBOXES);
store.commit(`labels/${types.SET_LABELS}`, LABELS);
store.commit(`agents/${types.SET_AGENTS}`, [AGENTE]);

// Rota por variante (useRoute/useRouter das páginas nativas).
const rota = reactive({
  name: 'home',
  params: { accountId: 1 },
  query: {},
  path: '/app/accounts/1/dashboard',
  meta: {},
});
provide(routeLocationKey, rota);
provide(routerKey, {
  push: () => Promise.resolve(),
  replace: () => Promise.resolve(),
  resolve: () => ({ href: '#' }),
  currentRoute: { value: rota },
});

const ir = (nome, params = {}, extra = {}) => {
  Object.assign(rota, { name: nome, params: { accountId: 1, ...params } });
  respostas = { ...API, ...extra };
};
// Conversa aberta no painel = card ativo da lista.
const abrirConversa = (extra = {}) => {
  ir('home', {}, extra);
  setTimeout(
    () => store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: 103 }),
    1000
  );
};
// Aba "Todas" (o card mostra o responsável): clique na 3ª aba.
const abaTodas = () => {
  abrirConversa();
  setTimeout(
    () =>
      document.querySelectorAll('.conversations-list-wrap li a')[2]?.click(),
    1500
  );
};
</script>

<template>
  <Story
    title="Ramon/Conversas e Contatos (nativas)"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Conversas" :init-state="() => abrirConversa()">
      <div class="flex h-screen bg-n-surface-1">
        <ChatList />
        <div class="flex-1 border-l border-n-weak" />
      </div>
    </Variant>
    <Variant title="Conversas todas" :init-state="abaTodas">
      <div class="flex h-screen bg-n-surface-1">
        <ChatList />
        <div class="flex-1 border-l border-n-weak" />
      </div>
    </Variant>
    <Variant
      title="Conversas com lead"
      :init-state="
        () =>
          abrirConversa({
            conversations: {
              data: { meta: STATS, payload: CONVERSAS_COM_LEAD },
            },
          })
      "
    >
      <div class="flex h-screen bg-n-surface-1">
        <ChatList />
        <div class="flex-1 border-l border-n-weak" />
      </div>
    </Variant>
    <Variant
      title="Conversas vazia"
      :init-state="
        () =>
          ir(
            'home',
            {},
            {
              conversations: {
                data: {
                  meta: { mine_count: 0, unassigned_count: 0, all_count: 0 },
                  payload: [],
                },
              },
            }
          )
      "
    >
      <div class="flex h-screen bg-n-surface-1">
        <ChatList />
        <div class="flex-1 border-l border-n-weak" />
      </div>
    </Variant>
    <Variant
      title="Contatos"
      :init-state="() => ir('contacts_dashboard_index')"
    >
      <div class="h-screen"><ContactsIndex /></div>
    </Variant>
    <Variant
      title="Contatos vazio"
      :init-state="
        () =>
          ir(
            'contacts_dashboard_index',
            {},
            { contacts: { payload: [], meta: { count: 0 } } }
          )
      "
    >
      <div class="h-screen"><ContactsIndex /></div>
    </Variant>
    <Variant
      title="Contato detalhe"
      :init-state="() => ir('contacts_edit', { contactId: '1' })"
    >
      <div class="h-screen"><ContactManageView /></div>
    </Variant>
    <Variant
      title="Contato detalhe com lead"
      :init-state="
        () =>
          ir(
            'contacts_edit',
            { contactId: '1' },
            { 'contacts/1/linha_da_vida': LINHA_DA_VIDA }
          )
      "
    >
      <div class="h-screen"><ContactManageView /></div>
    </Variant>
  </Story>
</template>
