<script setup>
// Story das Automações (B2) — prints de aprovação claro/escuro. Sem rede:
// window.axios responde com dados FICTÍCIOS por URL. Fluxo = o do mockup,
// só com passos da B1.
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import Lista from './Lista.vue';
import Editor from './Editor.vue';
import Execucao from './Execucao.vue';
import { MODELOS } from './modelos';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const atras = ms => new Date(Date.now() - ms).toISOString();
const no = (id, tipo, config, x, y) => ({
  id,
  tipo,
  config,
  posicao: { x, y },
});
const GRAFO = {
  nos: [
    no(
      'n1',
      'gatilho',
      { tipo: 'lead_mudou_etapa', para_etapa_ids: [4] },
      300,
      0
    ),
    no(
      'n2',
      'rascunho_texto',
      { rotulo: 'Boas-vindas', texto: 'Olá, {nome}! Seja bem-vindo(a).' },
      300,
      120
    ),
    no(
      'n3',
      'criar_tarefa',
      { titulo: 'Conferir documentos', tipo: 'document', prazo_dias: 1 },
      300,
      265
    ),
    no('n4', 'esperar', { quantidade: 2, unidade: 'dias' }, 300, 385),
    no(
      'n5',
      'se',
      {
        rotulo: 'Documentos completos?',
        juncao: 'e',
        condicoes: [
          { campo: 'etiquetas', operador: 'contem', valor: 'docs-ok' },
        ],
      },
      300,
      505
    ),
    no('n6', 'mover_etapa', { etapa_id: 5 }, 80, 660),
    no(
      'n7',
      'rascunho_texto',
      {
        rotulo: 'Lembrete dos documentos',
        texto: 'Oi, {nome}! Passando para lembrar dos documentos.',
      },
      520,
      660
    ),
    no(
      'n8',
      'avisar_push',
      { texto: '{nome} ainda deve documentos' },
      520,
      805
    ),
  ],
  setas: [
    { de: 'n1', saida: 's', para: 'n2' },
    { de: 'n2', saida: 's', para: 'n3' },
    { de: 'n3', saida: 's', para: 'n4' },
    { de: 'n4', saida: 's', para: 'n5' },
    { de: 'n5', saida: 'sim', para: 'n6' },
    { de: 'n5', saida: 'nao', para: 'n7' },
    { de: 'n7', saida: 's', para: 'n8' },
  ],
};
const linha = (n, tipo, saida, resumo, h) => ({
  no: n,
  tipo,
  em: atras(h * 3600000),
  saida,
  resumo,
  erro: false,
});
const EXEC = {
  id: 412,
  fluxo_id: 1,
  versao: 3,
  alvo_type: 'Lead',
  alvo_id: 231,
  alvo_nome: 'Maria da Silva',
  lead_id: 231,
  conversation_display_id: 1802,
  status: 'concluida',
  ensaio: false,
  no_atual: null,
  retomar_em: null,
  erro: null,
  created_at: atras(2 * DIA),
  updated_at: atras(0),
  grafo: GRAFO,
  trilha: [
    linha('n1', 'gatilho', 's', 'lead_mudou_etapa', 48),
    linha(
      'n2',
      'rascunho_texto',
      's',
      'rascunho criado: Olá, Maria! Seja bem-vindo(a).',
      48
    ),
    linha('n3', 'criar_tarefa', 's', 'tarefa "Conferir documentos" · Ana', 48),
    linha('n4', 'esperar', 's', 'espera até 04/10 14:31', 48),
    linha('n5', 'se', 'nao', 'não', 1),
    linha(
      'n7',
      'rascunho_texto',
      's',
      'rascunho criado: Oi, Maria! Passando para lembrar dos documentos.',
      1
    ),
    linha('n8', 'avisar_push', 's', 'push: Maria ainda deve documentos', 1),
  ],
};
const FLUXO = {
  id: 1,
  nome: 'Pós-contrato: pedir documentos',
  descricao: null,
  gatilho_tipo: 'lead_mudou_etapa',
  ativo: true,
  limite_dia: 20,
  origem: 'usuario',
  sistema_chave: null,
  modo: 'normal',
  versao: 3,
  editado_em: atras(DIA),
  hoje: 3,
  esperando: 8,
  falharam_24h: 0,
  ultima_em: atras(12 * 60000),
  rascunho: GRAFO,
  versoes: [3, 2, 1].map(n => ({ numero: n, created_at: atras(n * DIA) })),
};
const API = {
  ramon_fluxos: {
    payload: [
      FLUXO,
      {
        ...FLUXO,
        id: 2,
        nome: 'Fora do horário',
        gatilho_tipo: 'mensagem_recebida',
        versao: 2,
        limite_dia: 50,
        hoje: 14,
        esperando: 0,
        ultima_em: atras(4 * 60000),
      },
      {
        ...FLUXO,
        id: 3,
        nome: 'Lead ganho',
        gatilho_tipo: 'lead_ganho',
        versao: 1,
        limite_dia: null,
        hoje: 1,
        esperando: 0,
        falharam_24h: 1,
        ultima_em: atras(3600000),
      },
      {
        ...FLUXO,
        id: 4,
        nome: 'Rodar na mão: pedir documentos',
        gatilho_tipo: null,
        versao: null,
        ativo: false,
        hoje: 0,
        esperando: 0,
        ultima_em: null,
      },
    ],
    resumo: { ligados: 3, total: 4, hoje: 18, esperando: 8, falharam_24h: 1 },
  },
  'ramon_fluxos/1': FLUXO,
  'ramon_fluxos/1/execucoes': {
    payload: [
      { ...EXEC, grafo: undefined },
      {
        ...EXEC,
        id: 411,
        ensaio: true,
        alvo_nome: 'João Pereira',
        created_at: atras(3 * DIA),
      },
    ],
  },
  'ramon_fluxos/1/execucoes/412': EXEC,
  // B2b: opções do passo ADVBOX e assistentes/skills do Captain
  'ramon_fluxos/opcoes_advbox': {
    usuarios: [
      { id: 11, nome: 'Ana Souza' },
      { id: 12, nome: 'Carlos Lima' },
    ],
    tipos_tarefa: [
      { id: 21, nome: 'Conferir documentos' },
      { id: 22, nome: 'Protocolar requerimento' },
    ],
  },
  'captain/assistants': {
    payload: [
      { id: 1, name: 'Assistente Previdenciário' },
      { id: 2, name: 'Assistente Trabalhista' },
    ],
  },
  'captain/assistants/1/scenarios': {
    payload: [
      { id: 31, title: 'Resumir documentos recebidos' },
      { id: 32, title: 'Montar checklist do caso' },
    ],
  },
};
const responder = async url => ({
  data: API[url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '')] ?? {
    payload: [],
  },
});
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const rota = reactive({
  name: 'captain_automacoes_index',
  params: { accountId: 1, fluxoId: '1', execId: '412' },
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
store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  name: 'Eduardo Schlata',
  ui_settings: {},
  accounts: [
    { id: 1, role: 'administrator', permissions: ['administrator', 'agent'] },
  ],
});
// módulos namespaced: leadConfig, agents, theses, inboxes (store/modules/*)
store.commit(`leadConfig/${types.SET_LEAD_CONFIG}`, {
  stages: [
    { id: 4, name: 'Contrato assinado', position: 4 },
    { id: 5, name: 'Documentação OK', position: 5 },
  ],
  priorities: [],
});
store.commit(`inboxes/${types.SET_INBOXES}`, [
  { id: 7, name: 'WhatsApp Escritório', channel_type: 'Channel::Whatsapp' },
]);
store.commit(`agents/${types.SET_AGENTS}`, [
  { id: 1, name: 'Ana Souza', confirmed: true },
]);
store.commit(`theses/${types.SET_THESES}`, [
  { id: 1, name: 'Auxílio-acidente', position: 0 },
]);

const comNo = id => () => {
  rota.query = { no: id };
};
// B2b: o editor abre com o modelo Pós-contrato; `ajusta` troca o que cada tela mostra
const posContrato = ajusta => () => {
  const g = structuredClone(
    MODELOS.find(m => m.chave === 'pos_contrato').desenho
  );
  const passo = id => g.nos.find(n => n.id === id);
  ajusta?.(passo);
  FLUXO.rascunho = g;
};
const trocaPasso = (id, tipo, config) => passo => {
  Object.assign(passo(id), { tipo, config });
};
// o Editor ignora ?no=, então o passo abre por clique no nó do quadro
const abrePasso = (id, ajusta) => () => {
  posContrato(ajusta)();
  setTimeout(
    () =>
      document.querySelector(`.vue-flow__node[data-id="${id}"] > *`)?.click(),
    3000
  );
};
const clicarEm = texto => () =>
  setTimeout(
    () =>
      [...document.querySelectorAll('button')]
        .find(b => b.textContent.includes(texto))
        ?.click(),
    2000
  );
const rolarPaleta = () =>
  setTimeout(() => {
    const p = document.querySelector('[data-testid="fluxo-paleta"]');
    if (p) p.scrollTop = p.scrollHeight;
  }, 3000);
const paletaAoFim = () => {
  posContrato()();
  clicarEm('Adicionar passo')();
  rolarPaleta();
};
</script>

<template>
  <Story title="Captain/Automações" :layout="{ type: 'single', iframe: true }">
    <Variant title="Lista">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant title="Novo" :init-state="clicarEm('Novo fluxo')">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant title="Editor" :init-state="comNo('n7')">
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="Paleta" :init-state="clicarEm('Adicionar passo')">
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="PosContrato" :init-state="posContrato()">
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="PaletaB2b" :init-state="paletaAoFim">
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant
      title="PainelIa"
      :init-state="
        abrePasso(
          'n6',
          trocaPasso('n6', 'rascunho_ia', {
            rotulo: 'Lembrete dos documentos',
            instrucao:
              'Lembre {nome}, com gentileza, dos documentos que ainda faltam. Não prometa resultado nem prazo.',
          })
        )
      "
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant
      title="PainelSkill"
      :init-state="
        abrePasso(
          'n6',
          trocaPasso('n6', 'rodar_skill', {
            rotulo: 'Resumir documentos',
            assistente_id: 1,
            skill_id: 31,
            instrucao: 'Resuma os documentos que {nome} enviou.',
          })
        )
      "
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant
      title="PainelAdvbox"
      :init-state="
        abrePasso(
          'n3',
          trocaPasso('n3', 'advbox', {
            rotulo: 'Tarefa no ADVBOX',
            acao: 'tarefa',
            tipo_tarefa_id: 21,
            responsavel_id: 11,
            prazo_dias: 2,
            descricao: 'Conferir os documentos enviados por {nome}.',
          })
        )
      "
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant
      title="PainelWebhook"
      :init-state="
        abrePasso(
          'n7',
          trocaPasso('n7', 'webhook', {
            rotulo: 'Avisar o n8n',
            url: 'https://n8n.exemplo.com.br/webhook/pos-contrato',
          })
        )
      "
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant
      title="GatilhoRelogio"
      :init-state="
        abrePasso(
          'n1',
          trocaPasso('n1', 'gatilho', {
            tipo: 'lead_parado',
            dias: 3,
            hora: '11:00',
          })
        )
      "
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="Execucao">
      <div class="h-screen"><Execucao /></div>
    </Variant>
  </Story>
</template>
