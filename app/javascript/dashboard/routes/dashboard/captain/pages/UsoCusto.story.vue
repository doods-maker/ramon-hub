<script setup>
// Story da tela Uso e custo (Inteligência) — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS por URL.
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import UsoCusto from './UsoCusto.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const iso = n => new Date(Date.now() - n * DIA).toISOString().slice(0, 10);
// 30 dias de custo com cara de operação: dia útil gasta mais, fim de semana quase nada.
const CUSTOS = [
  0.82, 1.14, 0.97, 1.31, 0.12, 0.08, 1.05, 1.22, 1.48, 0.91, 1.17, 0.1, 0.06,
  1.36, 1.02, 1.29, 1.61, 1.4, 0.15, 0.09, 1.11, 1.57, 1.33, 1.24, 1.72, 0.18,
  0.11, 1.46, 1.38, 1.53,
];
const POR_DIA = CUSTOS.map((custo, i) => ({
  dia: iso(CUSTOS.length - 1 - i),
  custo_usd: custo,
  chamadas: Math.round(custo * 140),
}));

const linha = (chave, chamadas, entrada, saida, custo, erros, nome) => ({
  chave,
  chamadas,
  input_tokens: entrada,
  output_tokens: saida,
  custo_usd: custo,
  erros: erros ?? 0,
  ...(nome ? { nome } : {}),
});

const MODELOS = [
  { id: 'deepseek-chat', display_name: 'DeepSeek Chat', provider: 'deepseek' },
  {
    id: 'deepseek-v4-flash',
    display_name: 'DeepSeek V4 Flash',
    provider: 'deepseek',
  },
  {
    id: 'deepseek-v4-pro',
    display_name: 'DeepSeek V4 Pro',
    provider: 'deepseek',
  },
  {
    id: 'claude-haiku-4-5',
    display_name: 'Claude Haiku 4.5',
    provider: 'anthropic',
  },
  {
    id: 'claude-sonnet-4-6',
    display_name: 'Claude Sonnet 4.6',
    provider: 'anthropic',
  },
  { id: 'gpt-4.1-mini', display_name: 'GPT-4.1 Mini', provider: 'openai' },
  { id: 'gpt-5-mini', display_name: 'GPT-5 Mini', provider: 'openai' },
];

const USO = {
  periodo: '30d',
  de: iso(29),
  ate: iso(0),
  total: {
    chamadas: 4312,
    input_tokens: 18_420_000,
    output_tokens: 1_210_000,
    custo_usd: 29.97,
    erros: 14,
    sem_preco: 3,
  },
  por_dia: POR_DIA,
  por_funcao: [
    linha('atendimento', 1630, 11_900_000, 640_000, 21.84, 6),
    linha('copiloto', 1120, 2_810_000, 260_000, 3.12, 2),
    linha('advbox_pergunta', 214, 1_540_000, 92_000, 1.66),
    linha('fluxo', 512, 840_000, 61_000, 1.03, 3),
    linha('colheita', 96, 610_000, 48_000, 0.98),
    linha('doc_match', 402, 420_000, 31_000, 0.66, 1),
    linha('copiloto_noturno', 240, 220_000, 52_000, 0.42),
    linha('ata', 22, 80_000, 26_000, 0.26, 2),
  ],
  por_assistente: [
    linha(1, 1490, 10_800_000, 590_000, 19.9, 5, 'Atendimento (rascunho)'),
    linha(2, 140, 1_100_000, 50_000, 1.94, 1, 'Copiloto do Escritório'),
  ],
  por_modelo: [
    linha('deepseek-v4-pro', 1630, 11_900_000, 640_000, 21.84, 6),
    linha('deepseek-chat', 2660, 6_440_000, 544_000, 8.13, 8),
    linha('Systran/faster-whisper-medium', 22, 80_000, 26_000, null),
  ],
  hoje_usd: 1.53,
  teto_diario_usd: 2,
  agente: {
    hoje: 4,
    teto: 30,
    custo_hoje_usd: 1.86,
    execucoes_periodo: 61,
    custo_periodo_usd: 27.4,
  },
  fluxos: { hoje: 37, teto: 200 },
  chaves: { deepseek: true, openai: false, anthropic: true, claude_vps: true },
  escolhas: [
    {
      funcao: 'atendimento',
      feature: 'assistant',
      fonte: 'reserva',
      salvo: null,
      provider: 'deepseek',
      model: 'deepseek-v4-pro',
      modelos: MODELOS,
    },
    {
      funcao: 'copiloto',
      feature: 'copilot',
      fonte: 'tela',
      salvo: 'deepseek-chat',
      provider: 'deepseek',
      model: 'deepseek-chat',
      modelos: MODELOS,
    },
    {
      funcao: 'documentos',
      feature: 'documentos',
      fonte: 'tela',
      salvo: 'claude-haiku-4-5',
      provider: 'anthropic',
      model: 'claude-haiku-4-5',
      modelos: MODELOS,
    },
    {
      funcao: 'agente',
      feature: null,
      fonte: 'reserva',
      salvo: null,
      provider: 'claude_vps',
      model: 'claude-vps',
      modelos: [],
    },
  ],
};

// Conta nova: nada gravado ainda, sem teto.
const VAZIO = {
  ...USO,
  periodo: '7d',
  total: {
    chamadas: 0,
    input_tokens: 0,
    output_tokens: 0,
    custo_usd: null,
    erros: 0,
    sem_preco: 0,
  },
  por_dia: POR_DIA.slice(-7).map(dia => ({
    ...dia,
    custo_usd: 0,
    chamadas: 0,
  })),
  por_funcao: [],
  por_assistente: [],
  por_modelo: [],
  hoje_usd: 0,
  teto_diario_usd: null,
  agente: { ...USO.agente, hoje: 0, custo_periodo_usd: 0 },
  fluxos: { hoje: 0, teto: 200 },
};

let resposta = USO;
const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (path === 'ramon_ia_uso') return { data: resposta };
  return { data: {} };
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
    { id: 1, role: 'administrator', permissions: ['administrator', 'agent'] },
  ],
  ui_settings: {},
});

const vazio = () => {
  resposta = VAZIO;
};
</script>

<template>
  <Story title="Captain/Uso e custo" :layout="{ type: 'single', iframe: true }">
    <Variant title="Uso e custo">
      <div class="h-screen"><UsoCusto /></div>
    </Variant>
    <Variant title="Uso e custo vazio" :init-state="vazio">
      <div class="h-screen"><UsoCusto /></div>
    </Variant>
  </Story>
</template>
