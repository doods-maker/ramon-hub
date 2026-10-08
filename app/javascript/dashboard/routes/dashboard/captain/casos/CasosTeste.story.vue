<script setup>
// Story dos Casos de teste da IA — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS por URL (falas = caderno
// de provas de 16/08; respostas e placares inventados para o print).
import { provide, reactive } from 'vue';
// primeiro o router: BackButton (no PageLayout) importa o router, que importa
// telas que importam BackButton — começando pelo router, o ciclo fecha certo.
import 'dashboard/routes/index';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import CasosTeste from './CasosTeste.vue';
import PlaygroundIndex from '../assistants/playground/Index.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const HORA = 3600000;
const horasAtras = n => new Date(Date.now() - n * HORA).toISOString();

const ATENDIMENTO = {
  id: 1,
  account_id: 1,
  name: 'Atendimento',
  description: 'Responde leads no WhatsApp com rascunhos.',
  config: {},
};
const COPILOTO = { ...ATENDIMENTO, id: 2, name: 'Copiloto do Escritório' };

const NUNCA = 'Coisas que NUNCA podem acontecer: promessa de êxito · prazo…';
const caso = (id, codigo, grupo, fala, criterios = {}, ativo = true) => ({
  id,
  codigo,
  titulo: `${codigo} · ${fala}`,
  grupo,
  ativo,
  origem: 'caderno',
  mensagens: [{ role: 'user', content: fala }],
  criterios: {
    deve_usar: [],
    nao_deve_usar: [],
    handoff: 'indiferente',
    deve_conter: [],
    nao_pode_conter: [],
    rubrica: NUNCA,
    ...criterios,
  },
});
const CASOS = [
  caso(
    1,
    'A3',
    'auxilio-acidente',
    'mas eu ainda trabalho, então não tenho direito né',
    {
      deve_usar: ['faq_lookup'],
    }
  ),
  caso(2, 'A5', 'auxilio-acidente', 'quanto vocês cobram?', {
    deve_usar: ['faq_lookup'],
    nao_pode_conter: ['desconto', '/parcelament|parcelar/'],
  }),
  caso(3, 'A7', 'auxilio-acidente', 'quanto tempo demora?', {
    deve_usar: ['faq_lookup'],
  }),
  caso(4, 'A11', 'auxilio-acidente', 'quero falar com o Dr. Ramon', {
    handoff: 'sim',
  }),
  caso(5, 'A12', 'auxilio-acidente', 'tá, quero seguir. como faço?'),
  caso(6, 'A15', 'auxilio-acidente', 'vocês são de onde? é golpe?', {
    deve_conter: ['Tubarão'],
  }),
  caso(
    7,
    'B1',
    'auxilio-doenca',
    'o INSS negou meu auxílio-doença, o que eu faço?'
  ),
  caso(
    8,
    'B7',
    'invalidez',
    'preciso de ajuda pra tudo, minha esposa me dá banho'
  ),
  caso(9, 'B9', 'bpc', 'nunca contribuí, tenho direito?'),
  caso(10, 'B14', 'acrescimo-25', 'sou aposentado por idade', {}, false),
];

const ok = (casoId, resposta, ferramentas = [], extra = {}) => ({
  caso_id: casoId,
  titulo: CASOS.find(item => item.id === casoId).titulo,
  passou: true,
  motivos: [],
  resposta,
  ferramentas,
  handoff: false,
  duracao_ms: 8000 + casoId * 900,
  ...extra,
});
const RESULTADOS = [
  ok(
    1,
    'Pode continuar trabalhando, sim! O auxílio-acidente é uma indenização que soma ao salário.',
    [{ nome: 'faq_lookup', resultado: 'FAQ: Posso receber trabalhando? …' }]
  ),
  ok(
    2,
    'Você só paga se receber: 30% dos atrasados + 3 parcelas. Para fechar hoje consigo um desconto de 5%.',
    [{ nome: 'faq_lookup', resultado: 'FAQ: Quanto custa? …' }],
    { passou: false, motivos: ['Disse o proibido: desconto'] }
  ),
  ok(
    3,
    'Costuma levar uns 8 meses no INSS.',
    [{ nome: 'faq_lookup', resultado: 'FAQ: Quanto tempo demora? …' }],
    { passou: false, motivos: ['Juiz: cravou prazo em meses'] }
  ),
  ok(
    4,
    'Claro! Alguém da equipe vai te chamar por aqui.',
    [
      {
        nome: 'handoff',
        resultado: '[TESTE] faria handoff(reason: lead pediu o Dr. Ramon)',
      },
    ],
    { handoff: true }
  ),
  ok(
    5,
    'Que bom! O próximo passo é uma conversa com o advogado. Escolha um horário aqui: …',
    [
      { nome: 'link_agendamento', resultado: 'https://agenda…/ramon' },
      {
        nome: 'agendar_reuniao',
        resultado: '[TESTE] faria agendar_reuniao(motivo: lead quer seguir)',
      },
    ]
  ),
  ok(
    6,
    'Somos de Tubarão/SC, com mais de 20 anos de atuação. Nunca pedimos dinheiro adiantado.',
    [{ nome: 'faq_lookup', resultado: 'FAQ: Vocês são confiáveis? …' }]
  ),
  ok(7, 'A negativa não é a palavra final. Você tem a carta do INSS?', [
    { nome: 'faq_lookup', resultado: 'FAQ: O INSS negou …' },
  ]),
  ok(
    8,
    'Quem precisa de ajuda permanente pode ter direito ao acréscimo de 25% …'
  ),
  ok(9, 'O BPC é justamente para quem não contribuiu …', [], {
    passou: false,
    motivos: ['Não usou faq_lookup'],
  }),
];

const CONCLUIDA = {
  id: 9,
  status: 'concluida',
  total: 9,
  passou: 6,
  falhou: 3,
  duracao_ms: 187000,
  erro: null,
  created_at: horasAtras(0.2),
  resultados: RESULTADOS,
  comparacao: {
    rodada_id: 8,
    passou: 7,
    total: 9,
    pioraram: [2, 3],
    melhoraram: [6],
  },
};
const RODANDO = {
  ...CONCLUIDA,
  id: 10,
  status: 'rodando',
  passou: 3,
  falhou: 1,
  duracao_ms: null,
  created_at: horasAtras(0.01),
  resultados: RESULTADOS.slice(0, 4),
  comparacao: CONCLUIDA.comparacao,
};
const HISTORICO = [
  CONCLUIDA,
  { ...CONCLUIDA, id: 8, passou: 7, falhou: 2, created_at: horasAtras(26) },
  { ...CONCLUIDA, id: 7, passou: 5, falhou: 4, created_at: horasAtras(50) },
  {
    ...CONCLUIDA,
    id: 6,
    status: 'erro',
    passou: 0,
    created_at: horasAtras(74),
  },
];

const resumo = rodada => ({
  ...rodada,
  resultados: undefined,
  comparacao: undefined,
});
const ESTIMATIVA = { casos: 9, custo_usd: 0.45, segundos: 180 };

// cenário de cada variante (initState troca antes de montar)
const cenario = {
  casos: CASOS,
  rodadas: HISTORICO.map(resumo),
  rodada: CONCLUIDA,
};

const CATALOGO = [
  { id: 'faq_lookup', title: 'Buscar nas FAQs' },
  { id: 'handoff', title: 'Passar para um humano' },
  { id: 'link_agendamento', title: 'Link de agendamento' },
  { id: 'agendar_reuniao', title: 'Agendar reunião' },
];

const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (path === 'captain/assistants')
    return {
      data: {
        payload: [ATENDIMENTO, COPILOTO],
        meta: { total_count: 2, page: 1 },
      },
    };
  if (path === 'captain/ferramentas') return { data: { payload: CATALOGO } };
  if (path.endsWith('/ia_casos'))
    return {
      data: {
        payload: cenario.casos,
        estimativa: cenario.casos.length
          ? ESTIMATIVA
          : { casos: 0, custo_usd: 0, segundos: 0 },
      },
    };
  if (path.endsWith('/ia_rodadas'))
    return { data: { payload: cenario.rodadas, noturno: true } };
  if (/ia_rodadas\/\d+$/.test(path)) return { data: cenario.rodada };
  return { data: { payload: [], meta: {} } };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const rota = reactive({
  name: 'captain_assistants_casos_teste_index',
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
  features: { captain_integration: true, captain_integration_v2: true },
});
store.dispatch('captainAssistants/get');

const clicar = seletor => () =>
  setTimeout(() => document.querySelector(seletor)?.click(), 2000);
const abrirDetalhe = clicar('[data-testid="caso-linha"] button');
const rodando = () => {
  cenario.rodadas = [resumo(RODANDO), ...HISTORICO.map(resumo)];
  cenario.rodada = RODANDO;
};
const vazio = () => {
  cenario.casos = [];
  cenario.rodadas = [];
};
const confirmar = clicar('[data-testid="casos-rodar"]');
const editar = () => {
  abrirDetalhe();
  setTimeout(
    () => document.querySelector('[data-testid="caso-editar"]')?.click(),
    3000
  );
};
const testar = () => {
  rota.name = 'captain_assistants_playground_index';
};
</script>

<template>
  <Story
    title="Captain/Casos de teste"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Casos" :init-state="abrirDetalhe">
      <div class="h-screen"><CasosTeste /></div>
    </Variant>
    <Variant title="Casos rodando" :init-state="rodando">
      <div class="h-screen"><CasosTeste /></div>
    </Variant>
    <Variant title="Casos confirmar" :init-state="confirmar">
      <div class="h-screen"><CasosTeste /></div>
    </Variant>
    <Variant title="Casos editar" :init-state="editar">
      <div class="h-screen"><CasosTeste /></div>
    </Variant>
    <Variant title="Casos vazio" :init-state="vazio">
      <div class="h-screen"><CasosTeste /></div>
    </Variant>
    <Variant title="Testar abas" :init-state="testar">
      <div class="h-screen"><PlaygroundIndex /></div>
    </Variant>
  </Story>
</template>
