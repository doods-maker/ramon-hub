<script setup>
// Story de Conteúdo + TV + Relatórios + Atalhos (aprovação visual por print,
// claro/escuro). Sem rede: window.axios responde com dados FICTÍCIOS por URL;
// imagens = caixas cinzas em SVG inline (nada externo).
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import Conteudo from './Conteudo.vue';
import TvBoard from './TvBoard.vue';
import Relatorios from './Relatorios.vue';
import ExternalShortcuts from './ExternalShortcuts.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const daquiA = (dias, h = 12) => {
  const d = new Date(Date.now() + dias * DIA);
  d.setHours(h, 0, 0, 0);
  return d.toISOString();
};

// Card de exemplo: caixa cinza neutra com o número do card.
const card = (n, total) =>
  `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350"><rect width="1080" height="1350" fill="#d4d4d4"/><rect x="90" y="140" width="700" height="60" rx="8" fill="#a3a3a3"/><rect x="90" y="230" width="560" height="60" rx="8" fill="#a3a3a3"/><text x="540" y="760" font-family="sans-serif" font-size="96" fill="#737373" text-anchor="middle">${n}/${total}</text></svg>`
  )}`;
const cards = total =>
  Array.from({ length: total }, (_, i) => card(i + 1, total));

const LEGENDA =
  'Teve o auxílio-doença cortado mesmo sem condições de voltar ao trabalho? 🤔\n\nA alta programada não pode ser automática: se a incapacidade continua, você pode pedir a prorrogação e, se negada, discutir na Justiça. 📌\n\nSalve este post e mande pra quem precisa. 💬';

const BASE = {
  tese: 'Restabelecimento B31',
  tipo: 'carrossel',
  legenda: LEGENDA,
  conteudo: {
    fields: {
      titulo: 'Alta programada não é o fim',
      subtitulo: 'O que fazer quando o INSS corta o benefício',
      card_2: 'Pedido de prorrogação: até 15 dias antes da data de cessação.',
      card_3: 'Negado? Recurso administrativo ou ação judicial com perícia.',
    },
  },
};

const PECAS = [
  {
    ...BASE,
    id: 1,
    status: 'rascunho',
    gancho: 'Alta programada: o INSS pode cortar seu benefício?',
  },
  {
    ...BASE,
    id: 2,
    status: 'rascunho',
    tipo: 'estatico',
    tese: 'Auxílio-acidente (B94)',
    gancho: 'Sequela leve também dá direito ao auxílio-acidente',
  },
  {
    ...BASE,
    id: 3,
    status: 'montando',
    gancho: 'BPC/LOAS: renda da família não é tudo',
    tese: 'BPC/LOAS',
    travada: true,
  },
  {
    ...BASE,
    id: 4,
    status: 'aprovado',
    gancho: '5 documentos para pedir a aposentadoria por invalidez',
    tese: 'Aposentadoria invalidez (B32)',
  },
  {
    ...BASE,
    id: 5,
    status: 'montado',
    gancho: 'Perícia negada? Veja o que fazer',
    capa: card(1, 5),
    imagens: cards(5),
    sugestao_horario: daquiA(2),
    colaboradores: ['ramon_antonio__'],
  },
  {
    ...BASE,
    id: 6,
    status: 'agendado',
    gancho: 'Doença ocupacional e o INSS',
    capa: card(1, 4),
    imagens: cards(4),
    agendado_para: daquiA(1),
  },
  {
    ...BASE,
    id: 7,
    status: 'falhou',
    gancho: 'Quem tem direito ao auxílio-acidente',
    tipo: 'estatico',
    capa: card(1, 1),
    imagens: cards(1),
    agendado_para: daquiA(-1),
    erro: 'Instagram recusou a mídia (código 36003). Tente de novo.',
  },
  {
    ...BASE,
    id: 8,
    status: 'publicado',
    gancho: 'Carência: quando ela não é exigida',
    capa: card(1, 6),
    imagens: cards(6),
    permalink: '#',
  },
];
// Estados só das variantes novas (o quadro base fica igual ao "antes").
const EXTRAS = [
  {
    ...BASE,
    id: 9,
    status: 'publicando',
    gancho: 'Auxílio-acidente depois da alta',
    capa: card(1, 3),
    imagens: cards(3),
    agendado_para: daquiA(0, 0),
  },
  {
    ...BASE,
    id: 10,
    status: 'falhou',
    ambigua: true,
    gancho: 'Revisão da vida toda: o que mudou',
    capa: card(1, 5),
    imagens: cards(5),
    agendado_para: daquiA(-1),
    erro: 'Pode ter ido ao ar — conferir no Instagram antes de tentar de novo. (Net::ReadTimeout)',
  },
];
const COM_EXTRAS = { payload: [...PECAS, ...EXTRAS], token_ig: true };

const TV = {
  funnel: [
    { stage_id: 1, name: 'Novo', count: 12, is_won: false, is_lost: false },
    { stage_id: 2, name: 'Qualificação', count: 8, is_won: false },
    { stage_id: 3, name: 'Reunião', count: 5, is_won: false },
    { stage_id: 4, name: 'Assinatura', count: 2, is_won: false },
    { stage_id: 5, name: 'Ganho', count: 3, is_won: true },
  ],
  tv: {
    month: {
      won_value: 312000,
      won_count: 8,
      goal: 400000,
      business_days_left: 6,
      today: { won_count: 2, new_count: 9, avg_first_response_minutes: 18.4 },
    },
    by_thesis: [
      {
        thesis_id: 1,
        name: 'Restabelecimento B31',
        leads_count: 14,
        new_week: 5,
        won_month: 4,
        won_value_month: 146000,
        conversion_pct: 29,
        prescribing_count: 2,
        stalled_count: 1,
      },
      {
        thesis_id: 2,
        name: 'Auxílio-acidente (B94)',
        leads_count: 6,
        new_week: 1,
        won_month: 3,
        won_value_month: 84000,
        conversion_pct: 50,
        prescribing_count: 0,
        stalled_count: 0,
      },
      {
        thesis_id: 3,
        name: 'Aposentadoria invalidez (B32)',
        leads_count: 5,
        new_week: 0,
        won_month: 1,
        won_value_month: 24000,
        conversion_pct: 20,
        prescribing_count: 0,
        stalled_count: 2,
      },
      {
        thesis_id: 4,
        name: 'BPC/LOAS',
        leads_count: 4,
        new_week: 2,
        won_month: 0,
        won_value_month: 0,
        conversion_pct: 0,
        prescribing_count: 0,
        stalled_count: 0,
      },
      {
        thesis_id: null,
        name: 'Sem tese',
        leads_count: 3,
        new_week: 0,
        won_month: 0,
        won_value_month: 0,
        conversion_pct: null,
        prescribing_count: 0,
        stalled_count: 0,
      },
    ],
    race: [
      { name: 'Camila', won_count: 4, won_value: 168000 },
      { name: 'Eduardo', won_count: 3, won_value: 120000 },
      { name: 'Gabriela', won_count: 1, won_value: 24000 },
    ],
    prescribing_total_monthly: 11240,
    next_meeting: {
      at: daquiA(0, 16),
      lead_name: 'Antônio Carlos Nunes',
      user_name: 'Camila',
    },
    last_won: {
      lead_name: 'Zilda Pereira Lima',
      closer_name: 'Camila',
      value: 39800,
      benefit: 'Aposentadoria por invalidez',
    },
  },
};

// Painel de BI de mentira: caixas cinzas no lugar dos gráficos do Metabase.
const METABASE = `data:text/html;charset=utf-8,${encodeURIComponent(
  '<body style="margin:0;font-family:sans-serif;background:#f9fbfc;padding:24px;display:grid;grid-template-columns:repeat(3,1fr);gap:16px">' +
    [
      'Leads por semana',
      'Funil',
      'Origem',
      'Tempo de resposta',
      'Ganhos por tese',
      'Perdas',
    ]
      .map(
        nome =>
          `<div style="background:#fff;border:1px solid #e5e7eb;border-radius:8px;height:220px;padding:12px;color:#4c5773;font-size:14px">${nome}<div style="margin-top:12px;height:160px;background:#e5e7eb;border-radius:4px"></div></div>`
      )
      .join('') +
    '</body>'
)}`;

const ERRO = Symbol('erro');
const API = {
  ramon_conteudo: { payload: PECAS },
  ...Object.fromEntries(
    [...PECAS, ...EXTRAS].map(p => [`ramon_conteudo/${p.id}`, p])
  ),
  ramon_dashboard: TV,
  ramon_relatorios: { configured: true, url: METABASE },
};

let respostas = API;
const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (respostas[path] === ERRO) throw new Error('rede');
  return { data: respostas[path] ?? {} };
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
  accounts: [{ id: 1, role: 'administrator' }],
});

const com = extra => () => {
  respostas = { ...API, ...extra };
};
const comExtras =
  (gancho, tokenIg = true) =>
  () => {
    respostas = {
      ...API,
      ramon_conteudo: { ...COM_EXTRAS, token_ig: tokenIg },
    };
    // eslint-disable-next-line no-use-before-define
    if (gancho) abrir(gancho)();
  };
// TV sem fetch bem-sucedido há 5 min: o "atualizado em" nasce 5 min atrás.
const tvDesatualizada = () => {
  const real = Date.now;
  Date.now = () => real() - 5 * 60 * 1000;
  setTimeout(() => {
    Date.now = real;
  }, 3000);
};
// Atalho com URL inválida na 2ª linha.
const atalhoInvalido = () =>
  setTimeout(() => {
    const campo = document.querySelectorAll(
      '[data-testid="shortcut-url-input"]'
    )[1];
    campo.value = 'site invalido';
    campo.dispatchEvent(new Event('input'));
    campo.dispatchEvent(new Event('blur'));
  }, 1500);
// Abre a peça clicando no card (a peça aberta é estado interno da página).
const abrir = gancho => () =>
  setTimeout(
    () =>
      [...document.querySelectorAll('[data-testid="peca-card"]')]
        .find(el => el.textContent.includes(gancho))
        ?.click(),
    1500
  );
</script>

<template>
  <Story
    title="Ramon/Conteúdo, TV e Relatórios"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Conteudo">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo pauta"
      :init-state="abrir('Alta programada: o INSS')"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="Conteudo montando" :init-state="abrir('BPC/LOAS: renda')">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="Conteudo pronta" :init-state="abrir('Perícia negada')">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo agendada"
      :init-state="abrir('Doença ocupacional')"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="Conteudo falhou" :init-state="abrir('Quem tem direito')">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="Conteudo publicada" :init-state="abrir('Carência')">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo vazio"
      :init-state="com({ ramon_conteudo: { payload: [] } })"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="Conteudo erro" :init-state="com({ ramon_conteudo: ERRO })">
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo publicando"
      :init-state="comExtras('depois da alta')"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo falha ambigua"
      :init-state="comExtras('Revisão da vida toda')"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant
      title="Conteudo sem token"
      :init-state="comExtras('Perícia negada', false)"
    >
      <div class="h-screen"><Conteudo /></div>
    </Variant>
    <Variant title="TV">
      <TvBoard />
    </Variant>
    <Variant
      title="TV sem meta"
      :init-state="
        com({
          ramon_dashboard: {
            ...TV,
            tv: {
              ...TV.tv,
              month: { ...TV.tv.month, goal: 0 },
              race: [],
              next_meeting: null,
              last_won: null,
            },
          },
        })
      "
    >
      <TvBoard />
    </Variant>
    <Variant title="TV desatualizada" :init-state="tvDesatualizada">
      <TvBoard />
    </Variant>
    <Variant title="Relatorios">
      <div class="h-screen"><Relatorios /></div>
    </Variant>
    <Variant
      title="Relatorios nao configurado"
      :init-state="com({ ramon_relatorios: { configured: false } })"
    >
      <div class="h-screen"><Relatorios /></div>
    </Variant>
    <Variant
      title="Relatorios erro"
      :init-state="com({ ramon_relatorios: ERRO })"
    >
      <div class="h-screen"><Relatorios /></div>
    </Variant>
    <Variant title="Atalhos">
      <div class="h-screen"><ExternalShortcuts /></div>
    </Variant>
    <Variant title="Atalhos erro" :init-state="atalhoInvalido">
      <div class="h-screen"><ExternalShortcuts /></div>
    </Variant>
  </Story>
</template>
