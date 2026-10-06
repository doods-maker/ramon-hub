<script setup>
// Story do Painel do time — aprovação visual por print, claro/escuro. Sem
// rede: window.axios responde com dados FICTÍCIOS pelo papel pedido. Papel
// do usuário (gestor × SDR) via auth/currentUser.
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import PainelTime from './PainelTime.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const kpi = (valor, num, den) => ({ valor, num, den });
const diaria = valores =>
  valores.map((n, i) => ({
    inicio: `2026-10-${String(i + 1).padStart(2, '0')}`,
    n,
  }));
const semanal = valores =>
  valores.map((n, i) => ({
    inicio: `2026-10-${String(1 + i * 7).padStart(2, '0')}`,
    n,
  }));

const METAS = {
  sdr: {
    primeira_resposta: { alvo: 5, sentido: 'max', unidade: 'min' },
    sem_resposta: { alvo: 0, sentido: 'max', unidade: 'n' },
    qualificado_agendada: { alvo: 70, sentido: 'min', unidade: '%' },
    show: { alvo: 75, sentido: 'min', unidade: '%' },
    nao_qualificada: { alvo: 15, sentido: 'max', unidade: '%' },
    registro_completo: { alvo: 100, sentido: 'min', unidade: '%' },
  },
  closer: {
    conversao: { alvo: 50, sentido: 'min', unidade: '%' },
    assinado_na_reuniao: { alvo: 80, sentido: 'min', unidade: '%' },
    docs_7d: { alvo: 80, sentido: 'min', unidade: '%' },
    cancelamento_7d: { alvo: 5, sentido: 'max', unidade: '%' },
    painel: { alvo: 100, sentido: 'min', unidade: '%' },
    dossie_24h: { alvo: 100, sentido: 'min', unidade: '%' },
    vou_pensar_48h: { alvo: 100, sentido: 'min', unidade: '%' },
  },
};

const sdr = (user, meta, realizado, k, serie) => ({
  user,
  meta_mes: { mes: '2026-10', meta, realizado, dias_uteis_restantes: 6 },
  kpis: {
    primeira_resposta: kpi(...k[0]),
    sem_resposta: kpi(...k[1]),
    registro_completo: kpi(...k[2]),
    qualificado_agendada: kpi(...k[3]),
    show: kpi(...k[4]),
    nao_qualificada: kpi(...k[5]),
  },
  volume: { total: serie.reduce((s, n) => s + n, 0), serie: diaria(serie) },
});
const LARISSA = sdr(
  { id: 11, name: 'Larissa Bittencourt' },
  25,
  18,
  [
    [3, 61, null],
    [2, 2, 4],
    [88, 53, 60],
    [74, 26, 35],
    [71, 22, 31],
    [11, 2, 18],
  ],
  [5, 7, 3, 0, 0, 8, 6, 4, 9, 7, 0, 0, 5, 6, 8, 4, 3]
);
const BRUNA = sdr(
  { id: 13, name: 'Bruna Fernandes Kock' },
  null,
  4,
  [
    [8.5, 20, null],
    [0, 0, 1],
    [100, 18, 18],
    [62, 8, 13],
    [80, 4, 5],
    [25, 1, 4],
  ],
  [2, 1, 0, 0, 0, 3, 2, 1, 2, 1, 0, 0, 2, 1, 2, 1, 0]
);
const SDR_TIME = sdr(
  null,
  25,
  22,
  [
    [3.5, 81, null],
    [2, 2, 5],
    [91, 71, 78],
    [71, 34, 48],
    [72, 26, 36],
    [14, 3, 22],
  ],
  [7, 8, 3, 0, 0, 11, 8, 5, 11, 8, 0, 0, 7, 7, 10, 5, 3]
);

const RAFAEL = {
  user: { id: 12, name: 'Rafael Cardoso Lemos' },
  meta_mes: {
    mes: '2026-10',
    meta: 12,
    realizado: 8,
    dias_uteis_restantes: 6,
    aguardando: 3,
  },
  kpis: {
    conversao: kpi(52.4, 11, 21),
    assinado_na_reuniao: kpi(72.7, 8, 11),
    vou_pensar_48h: kpi(66.7, 2, 3),
    docs_7d: kpi(81.8, 9, 11),
    cancelamento_7d: kpi(0, 0, 9),
    painel: kpi(63.6, 7, 11),
    dossie_24h: kpi(90.9, 10, 11),
  },
  volume: { total: 11, serie: semanal([2, 4, 3, 2]) },
};

const papelDo = config => config?.params?.papel || 'sdr';
const RESPOSTAS = {
  admin: {
    sdr: { time: SDR_TIME, pessoas: [LARISSA, BRUNA] },
    closer: { time: { ...RAFAEL, user: null }, pessoas: [RAFAEL] },
  },
  agente: { sdr: { time: null, pessoas: [LARISSA] } },
  vazio: {
    sdr: { time: { ...SDR_TIME, user: null }, pessoas: [] },
    closer: { time: null, pessoas: [] },
  },
};

let cenario = 'admin';
const responder = async (_url, config) => {
  const papel = papelDo(config);
  const corpo = RESPOSTAS[cenario][papel] ?? { time: null, pessoas: [] };
  return {
    data: { papel, periodo: 'mes', metas: METAS[papel], ...corpo },
  };
};
window.axios = { get: responder };

const store = useStore();
store.registerModule('route', { state: { params: { accountId: 1 } } });
const papel = role =>
  store.commit('SET_CURRENT_USER', {
    id: role === 'administrator' ? 1 : 11,
    accounts: [{ id: 1, role }],
  });

const clicar = testid =>
  setTimeout(
    () => document.querySelector(`[data-testid="${testid}"]`)?.click(),
    1500
  );

const sdrAdmin = () => {
  cenario = 'admin';
  papel('administrator');
};
const closerAdmin = () => {
  sdrAdmin();
  clicar('painel-papel-closer');
};
const sdrAgente = () => {
  cenario = 'agente';
  papel('agent');
};
const vazio = () => {
  cenario = 'vazio';
  papel('administrator');
};
</script>

<template>
  <Story title="Ramon/Painel do time" :layout="{ type: 'single' }">
    <Variant title="SDR admin" :init-state="sdrAdmin">
      <div class="h-screen"><PainelTime /></div>
    </Variant>
    <Variant title="Closer admin" :init-state="closerAdmin">
      <div class="h-screen"><PainelTime /></div>
    </Variant>
    <Variant title="SDR agente" :init-state="sdrAgente">
      <div class="h-screen"><PainelTime /></div>
    </Variant>
    <Variant title="Vazio" :init-state="vazio">
      <div class="h-screen"><PainelTime /></div>
    </Variant>
  </Story>
</template>
