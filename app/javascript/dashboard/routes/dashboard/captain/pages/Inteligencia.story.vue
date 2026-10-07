<script setup>
// Story da área Inteligência (pacote A1) — aprovação visual por print,
// claro/escuro. Sem rede: window.axios responde com dados FICTÍCIOS por URL.
// Variantes com diálogo clicam no botão depois de montar (pelo texto).
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import AssistantsIndex from '../assistants/Index.vue';
import ResponsesIndex from '../responses/Index.vue';
import ResponsesPending from '../responses/Pending.vue';
import DocumentsIndex from '../documents/Index.vue';
import ScenariosIndex from '../assistants/scenarios/Index.vue';
import CustomToolsIndex from '../tools/Index.vue';
import PlaygroundIndex from '../assistants/playground/Index.vue';
import InboxesIndex from '../assistants/inboxes/Index.vue';
import SettingsIndex from '../assistants/settings/Settings.vue';
import GuardrailsIndex from '../assistants/guardrails/Index.vue';
import GuidelinesIndex from '../assistants/guidelines/Index.vue';
import Execucoes from './Execucoes.vue';
import VisaoGeral from './VisaoGeral.vue';
import FerramentasPage from './Ferramentas.vue';
import TOOLS_YML from '../../../../../../../config/agents/tools.yml';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';
// Produção desde 17/08 (D7): conversas novas começam em Piloto com limites.
window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();
const unix = n => Math.floor((Date.now() - n * DIA) / 1000);

const ATENDIMENTO = {
  id: 1,
  account_id: 1,
  name: 'Atendimento (rascunho)',
  description:
    'Responde leads no WhatsApp com rascunhos para a equipe revisar.',
  config: {
    product_name: 'Ramon Antônio Advogados',
    feature_faq: false,
    feature_memory: false,
    feature_citation: false,
    feature_contact_attributes: true,
    handoff_message: 'Vou chamar alguém da equipe para seguir com você.',
    resolution_message: 'Qualquer dúvida, é só chamar por aqui.',
    instructions: 'Você atende leads da banca no WhatsApp.',
    temperature: 0.3,
  },
  guardrails: [],
  response_guidelines: [],
  created_at: unix(60),
  updated_at: unix(1),
};
const COPILOTO = {
  ...ATENDIMENTO,
  id: 2,
  name: 'Copiloto do Escritório',
  description: 'Ajuda a equipe com AdvBox, cálculos e funil.',
};

const CATALOGO = [
  { id: 'faq_lookup', title: 'Buscar nas FAQs', nivel: 'consulta' },
  { id: 'playbook_da_tese', title: 'Playbook da tese', nivel: 'consulta' },
  {
    id: 'registrar_qualificacao',
    title: 'Registrar qualificação',
    nivel: 'interna',
  },
  {
    id: 'documentacao_faltante',
    title: 'O que falta no caso',
    nivel: 'consulta',
  },
  { id: 'solicitar_documento', title: 'Pedir documentos', nivel: 'rascunho' },
  {
    id: 'enviar_link_portal',
    title: 'Link do portal do cliente',
    nivel: 'rascunho',
  },
  { id: 'link_agendamento', title: 'Link de agendamento', nivel: 'consulta' },
  { id: 'agendar_reuniao', title: 'Agendar reunião', nivel: 'sugestao' },
  { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
  {
    id: 'consultar_dossie_advbox',
    title: 'Consultar dossiê no AdvBox',
    nivel: 'consulta',
  },
  {
    id: 'add_private_note',
    title: 'Nota interna na conversa',
    nivel: 'interna',
  },
];
const link = id =>
  `[${CATALOGO.find(tool => tool.id === id).title}](tool://${id})`;

const SKILLS = [
  {
    id: 1,
    title: 'Lead quer saber se tem direito',
    description:
      'Quando o lead pergunta se o caso dele dá direito a benefício.',
    instruction: `Busque a resposta com ${link('faq_lookup')} e o ${link('playbook_da_tese')}. Confirmado um critério, use ${link('registrar_qualificacao')}.`,
    tools: ['faq_lookup', 'playbook_da_tese', 'registrar_qualificacao'],
    enabled: true,
  },
  {
    id: 2,
    title: 'Pedir documentos que faltam',
    description: 'Quando o caso está parado por falta de documento.',
    instruction: `Veja o que falta com ${link('documentacao_faltante')}, monte o pedido com ${link('solicitar_documento')} e mande o ${link('enviar_link_portal')}.`,
    tools: [
      'documentacao_faltante',
      'solicitar_documento',
      'enviar_link_portal',
    ],
    enabled: true,
    edited: true,
  },
  {
    id: 3,
    title: 'Lead aceitou a reunião',
    description: 'Quando o lead topa conversar com o advogado.',
    instruction: `Mande o ${link('link_agendamento')}; com a data combinada, use ${link('agendar_reuniao')} e ${link('mover_etapa')}.`,
    tools: ['link_agendamento', 'agendar_reuniao', 'mover_etapa'],
    enabled: true,
  },
  {
    id: 4,
    title: 'Lead só quer conversar',
    description: 'Quando o lead manda só um oi ou agradece.',
    instruction: 'Responda com cordialidade e pergunte como pode ajudar.',
    tools: null,
    enabled: true,
  },
  {
    id: 5,
    title: 'Lead pediu desconto no honorário',
    description: 'Quando o lead pede para baixar o 30% + 3.',
    instruction:
      'Explique com calma que o honorário é fixo e só é pago se o benefício sair.',
    tools: null,
    enabled: false,
    edited: false,
  },
];

const ASSISTENTE_FAQ = { id: 1, name: ATENDIMENTO.name };
const FAQS = [
  {
    id: 1,
    question: 'Quanto custa o trabalho de vocês?',
    answer:
      'O honorário é 30% dos atrasados + 3 benefícios, sem valor inicial e sem outra cobrança.',
    tese: 'geral',
    status: 'approved',
    assistant: ASSISTENTE_FAQ,
    documentable: null,
    created_at: unix(10),
    updated_at: unix(2),
  },
  {
    id: 2,
    question: 'Preciso levar algum documento na reunião?',
    answer: 'Traga RG, CPF e os laudos médicos que você tiver.',
    tese: 'auxilio-acidente',
    status: 'approved',
    assistant: ASSISTENTE_FAQ,
    documentable: { type: 'Conversation', display_id: 482 },
    created_at: unix(8),
    updated_at: unix(3),
  },
];
const PENDENTES = [
  {
    id: 3,
    question: 'Quem recebe auxílio-acidente pode continuar trabalhando?',
    answer:
      'Pode. O auxílio-acidente é uma indenização e não impede o trabalho.',
    tese: null,
    status: 'pending',
    assistant: ASSISTENTE_FAQ,
    documentable: {
      type: 'Captain::Document',
      name: 'Página do auxílio-acidente',
    },
    created_at: unix(1),
    updated_at: unix(1),
  },
];
const DOCS = [
  {
    id: 1,
    name: 'Página do auxílio-acidente',
    external_link: 'https://ramonantonio.adv.br/auxilio-acidente',
    status: 'available',
    assistant: ASSISTENTE_FAQ,
    created_at: unix(5),
    updated_at: unix(5),
  },
  {
    id: 2,
    name: 'Honorários — resumo da equipe',
    external_link: 'TEXT: Honorários — resumo da equipe_20261007093000000',
    text_document: true,
    status: 'available',
    sync_status: null,
    assistant: ASSISTENTE_FAQ,
    created_at: unix(1),
    updated_at: unix(1),
  },
];

const RUNS = [
  ['consultar_dossie_advbox', 'ok', 0.1],
  ['mover_etapa', 'ok', 0.3],
  ['solicitar_documento', 'ok', 0.5],
  ['add_private_note', 'erro', 0.7],
].map(([tool, status, dias], i) => ({
  id: i + 1,
  tool_name: tool,
  status,
  duration_ms: 420 + i * 130,
  params: { lead_id: '123' },
  resultado: 'resultado da ferramenta',
  lead_id: i === 3 ? null : 123,
  conversation_id: 482,
  assistant_id: 1,
  lead_nome: i === 3 ? null : 'Maria Souza',
  conversa_display_id: i === 3 ? null : 482,
  assistente_nome: ATENDIMENTO.name,
  created_at: diasAtras(dias),
}));

const AGENTE = [
  {
    id: 3,
    pedido: 'resuma o caso da Maria e veja se tem perícia marcada',
    status: 'ok',
    resumo:
      'Caso 123: auxílio-acidente, perícia marcada para 14/10 às 9h. Anotei na tarefa do AdvBox.',
    acoes: [{ tipo: 'advbox_tarefa', ref: 'resp=12 {"id": 991}' }],
    modelo: 'claude-opus',
    esforco: 'low',
    duracao_ms: 48000,
    lead_id: 123,
    lead_nome: 'Maria Souza',
    conversa_display_id: 482,
    created_at: diasAtras(0.05),
  },
  {
    id: 2,
    pedido: 'gere o PDF do cálculo e suba no Drive',
    status: 'erro',
    resumo: 'O motor de cálculos não respondeu.',
    acoes: [],
    modelo: 'claude-opus',
    esforco: 'medium',
    duracao_ms: 120000,
    lead_id: 77,
    lead_nome: 'José Ribeiro',
    conversa_display_id: 470,
    created_at: diasAtras(0.2),
  },
  {
    id: 1,
    pedido: 'quais documentos faltam?',
    status: 'cap',
    resumo: 'Cap diário atingido (30)',
    acoes: [],
    modelo: null,
    esforco: null,
    duracao_ms: null,
    lead_id: null,
    lead_nome: null,
    conversa_display_id: 455,
    created_at: diasAtras(1.1),
  },
];

// Catálogo real (tools.yml) com as skills e execuções fictícias acima.
const FERRAMENTAS = {
  payload: TOOLS_YML.map(tool => {
    const runs = RUNS.filter(run => run.tool_name === tool.id);
    return {
      ...tool,
      skills: SKILLS.filter(skill => (skill.tools || []).includes(tool.id)).map(
        skill => ({
          id: skill.id,
          title: skill.title,
          assistant_id: 1,
          assistant_name: ATENDIMENTO.name,
        })
      ),
      ultima_execucao_em: runs[0]?.created_at ?? null,
      execucoes_7d: runs.length,
      erros_7d: runs.filter(run => run.status === 'erro').length,
    };
  }),
};

const STATS = {
  payload: [
    {
      id: 1,
      name: ATENDIMENTO.name,
      description: ATENDIMENTO.description,
      publico: 'lead',
      skills_ativas: 6,
      faqs_aprovadas: 62,
      faqs_pendentes: 1,
      caixas: [
        {
          id: 7,
          name: 'WhatsApp Escritório',
          channel_type: 'Channel::Whatsapp',
        },
      ],
      conversas_por_modo: { rascunho: 2, piloto_limitado: 5 },
    },
    {
      id: 2,
      name: COPILOTO.name,
      description: COPILOTO.description,
      publico: 'equipe',
      skills_ativas: 9,
      faqs_aprovadas: 0,
      faqs_pendentes: 0,
      caixas: [],
      conversas_por_modo: {},
    },
  ],
};

const API = {
  'captain/assistants': {
    payload: [ATENDIMENTO, COPILOTO],
    meta: { total_count: 2, page: 1 },
  },
  'captain/assistants/1': ATENDIMENTO,
  'captain/assistants/tools': CATALOGO,
  'captain/assistants/stats': STATS,
  'captain/assistants/1/scenarios': {
    payload: SKILLS,
    meta: { total_count: 5, page: 1 },
  },
  'captain/assistants/1/inboxes': { payload: [], meta: {} },
  'captain/assistant_responses': {
    payload: FAQS,
    meta: { total_count: 2, page: 1 },
  },
  'captain/documents': { payload: DOCS, meta: { total_count: 2, page: 1 } },
  'captain/assistants/1/buscar_faq': {
    payload: FAQS.map(({ id, question, answer, tese }) => ({
      id,
      question,
      answer,
      tese,
    })),
  },
  ramon_agente_execucoes: {
    resumo: { hoje: 4, teto: 30, problemas_hoje: 1 },
    items: AGENTE,
  },
  'captain/custom_tools': { payload: [], meta: { total_count: 0, page: 1 } },
  'captain/ferramentas': FERRAMENTAS,
  captain_tool_runs: {
    resumo: {
      total_24h: 4,
      erros_24h: 1,
      por_tool: { consultar_dossie_advbox: 1, mover_etapa: 1 },
      tools: RUNS.map(run => run.tool_name).sort(),
    },
    items: RUNS,
    catalogo: CATALOGO,
  },
  ramon_inteligencia: {
    rascunhos: {
      igual: 9,
      editado: 6,
      descartado: 2,
      sem_resposta: 1,
      pendente: 1,
    },
    piloto: { conversas: 14, meta: 20, sem_correcao_pct: 53 },
    primeira_resposta: {
      com_ia: { conversas: 12, mediana_min: 3.5 },
      sem_ia: { conversas: 20, mediana_min: 42 },
    },
    transferencias: { total: 3, conversas: [482, 477, 470] },
    aprovacoes: {
      sugestoes: 3,
      sugestoes_por_tipo: { move_stage: 1, zapsign: 1, draft: 1 },
    },
    agente: {
      hoje: 4,
      teto: 30,
      problemas_hoje: 1,
      ultima_em: diasAtras(0.05),
    },
  },
  ramon_watchdog: {
    thresholds: {
      teto_diario: 3,
      intervalo_minimo_dias: 2,
      teto_copiloto_noturno: 15,
      horario_retomada: '11:00 (BRT)',
      horario_copiloto: '05:00 (BRT)',
    },
    counters: {
      retomadas_24h: 2,
      sugestoes_pendentes: 3,
      execucoes_24h: 4,
      parados_agora: 1,
    },
    items: [
      {
        lead_id: 12,
        name: 'Maria Souza',
        stage_name: 'Qualificação',
        dias_parado: 6,
        limite_da_etapa: 3,
        tentativas: 1,
        ultima_retomada_em: diasAtras(2),
        tarefa_aberta: false,
        conversation_id: 482,
      },
    ],
  },
};
const PENDENTES_RESP = {
  payload: PENDENTES,
  meta: { total_count: 1, page: 1 },
};

const responder = async (url, config) => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (
    path === 'captain/assistant_responses' &&
    config?.params?.status === 'pending'
  )
    return { data: PENDENTES_RESP };
  return { data: API[path] ?? { payload: [], meta: {} } };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

// As páginas leem :assistantId com useRoute(): rota fake.
const rota = reactive({
  name: 'captain_assistants_responses_index',
  params: { accountId: 1, assistantId: 1 },
  query: {},
});
provide(routeLocationKey, rota);
provide(routerKey, {
  push: () => {},
  replace: () => {},
  resolve: () => ({ href: '#' }),
  currentRoute: { value: rota },
});

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  name: 'Eduardo Schlata',
  accounts: [
    { id: 1, role: 'administrator', permissions: ['administrator', 'agent'] },
  ],
  ui_settings: {},
});
store.commit(`accounts/${types.ADD_ACCOUNT}`, {
  id: 1,
  features: {
    captain_integration: true,
    captain_integration_v2: true,
    custom_tools: true,
  },
});
store.commit(`inboxes/${types.SET_INBOXES}`, [
  { id: 7, name: 'WhatsApp Escritório', channel_type: 'Channel::Whatsapp' },
]);
store.dispatch('captainAssistants/get');

// Clica no botão cujo texto contém `texto`, depois de a tela montar.
const clicar = texto =>
  [...document.querySelectorAll('button')]
    .find(botao => botao.textContent.includes(texto))
    ?.click();
const clicarEm = texto => () => setTimeout(() => clicar(texto), 2000);
// Vários cliques em sequência (abrir diálogo e trocar de aba).
const clicarNaOrdem = textos => () =>
  textos.forEach((texto, i) => setTimeout(() => clicar(texto), 2000 + i * 600));
// Digita no "Testar pergunta" e clica em Testar.
const testarPergunta = texto => () =>
  setTimeout(() => {
    const campo = document.querySelector(
      '[data-testid="testar-pergunta-campo"]'
    );
    if (!campo) return;
    campo.value = texto;
    campo.dispatchEvent(new Event('input'));
    setTimeout(
      () =>
        [...document.querySelectorAll('button')]
          .find(botao => botao.textContent.trim() === 'Testar')
          ?.click(),
      200
    );
  }, 2000);
const abaAgente = () => {
  rota.query = { aba: 'agente' };
};

// Visão geral com o padrão antigo (antes da D7): título "Rumo ao piloto".
const modoRascunho = () => {
  window.chatwootConfig = { ramonCopilotoModoDefault: 'rascunho' };
};
</script>

<template>
  <Story
    title="Captain/Inteligência"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Assistentes">
      <div class="h-screen"><AssistantsIndex /></div>
    </Variant>
    <Variant title="FAQs">
      <div class="h-screen"><ResponsesIndex /></div>
    </Variant>
    <Variant title="FAQs pendentes">
      <div class="h-screen"><ResponsesPending /></div>
    </Variant>
    <Variant
      title="FAQs testar pergunta"
      :init-state="
        testarPergunta('posso trabalhar recebendo auxílio-acidente?')
      "
    >
      <div class="h-screen"><ResponsesIndex /></div>
    </Variant>
    <Variant title="Documentos">
      <div class="h-screen"><DocumentsIndex /></div>
    </Variant>
    <Variant
      title="Documentos novo"
      :init-state="clicarEm('Criar um novo documento')"
    >
      <div class="h-screen"><DocumentsIndex /></div>
    </Variant>
    <Variant
      title="Documentos novo texto"
      :init-state="clicarNaOrdem(['Criar um novo documento', 'Colar texto'])"
    >
      <div class="h-screen"><DocumentsIndex /></div>
    </Variant>
    <Variant title="Skills">
      <div class="h-screen"><ScenariosIndex /></div>
    </Variant>
    <Variant title="Skills desligadas" :init-state="clicarEm('Desligadas')">
      <div class="h-screen"><ScenariosIndex /></div>
    </Variant>
    <Variant title="Ferramentas">
      <div class="h-screen"><FerramentasPage /></div>
    </Variant>
    <Variant title="Ferramentas HTTP">
      <div class="h-screen"><CustomToolsIndex /></div>
    </Variant>
    <Variant title="Testar">
      <div class="h-screen"><PlaygroundIndex /></div>
    </Variant>
    <Variant title="Caixas">
      <div class="h-screen"><InboxesIndex /></div>
    </Variant>
    <Variant
      title="Caixas conectar"
      :init-state="clicarEm('Conectar uma nova caixa de entrada')"
    >
      <div class="h-screen"><InboxesIndex /></div>
    </Variant>
    <Variant title="Configuracoes">
      <div class="h-screen"><SettingsIndex /></div>
    </Variant>
    <Variant title="Protecoes">
      <div class="h-screen"><GuardrailsIndex /></div>
    </Variant>
    <Variant title="Diretrizes">
      <div class="h-screen"><GuidelinesIndex /></div>
    </Variant>
    <Variant title="Execucoes">
      <div class="h-screen"><Execucoes /></div>
    </Variant>
    <Variant title="Execucoes agente" :init-state="abaAgente">
      <div class="h-screen"><Execucoes /></div>
    </Variant>
    <Variant title="Visao geral">
      <div class="h-screen"><VisaoGeral /></div>
    </Variant>
    <Variant title="Visao geral rascunho" :init-state="modoRascunho">
      <div class="h-screen"><VisaoGeral /></div>
    </Variant>
  </Story>
</template>
