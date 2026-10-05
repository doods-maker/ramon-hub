<script setup>
// Story da tela Cálculos + simulador (aprovação visual por print, claro/
// escuro). Sem rede: window.axios responde com dados de exemplo por URL.
// Sem router: a rota é um objeto reativo injetado (o push só troca os params).
// Nomes fictícios; valores realistas em R$.
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Calculos from './Calculos.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const route = reactive({ params: {} });
provide(routeLocationKey, route);
provide(routerKey, {
  push: ({ params }) => {
    route.params = params || {};
  },
});

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });

const CNIS_RESUMO = {
  filename: 'CNIS-Joao-Carlos-Pereira.pdf',
  uploaded_at: '2026-10-05T09:12:00Z',
  nascimento: '1971-04-18',
  competencias: 318,
  vinculos: 6,
  avisos: [
    '03/2013: indicador PEXT pendente (remuneração extemporânea)',
    '11/2019: contribuição abaixo do mínimo',
  ],
};

const RASCUNHO = {
  id: 900,
  name: 'Rascunho',
  thesis_name: null,
  contact_sexo: 'M',
  cnis_resumo: null,
};
const RASCUNHO_CNIS = { ...RASCUNHO, cnis_resumo: CNIS_RESUMO };

const LEAD = {
  id: 42,
  name: 'João Carlos Pereira',
  contact_name: 'João Carlos Pereira',
  thesis_name: 'Auxílio-acidente (B36)',
  contact_data_nascimento: '1971-04-18',
  contact_sexo: 'M',
  cnis_resumo: CNIS_RESUMO,
};

const CNIS_DETALHE = {
  ...CNIS_RESUMO,
  vinculos_detalhe: [
    {
      seq: 1,
      tipo: 'EMPREGO',
      origem: 'Metalúrgica Vale do Itajaí Ltda',
      inicio: '1990-03-01',
      fim: '2004-11-30',
    },
    {
      seq: 2,
      tipo: 'EMPREGO',
      origem: 'Construtora Bom Jesus S.A.',
      inicio: '2005-02-01',
      fim: '2016-08-31',
    },
    {
      seq: 3,
      tipo: 'BENEFICIO',
      origem: 'Auxílio-doença previdenciário (B31)',
      inicio: '2016-09-01',
      fim: '2017-03-15',
    },
    {
      seq: 4,
      tipo: 'RECOLHIMENTO',
      origem: 'Contribuinte individual',
      inicio: '2018-01-01',
      fim: null,
    },
  ],
  parametros: { especiais: JSON.stringify({ 1: { grau: 25 } }) },
};

const PAINEL = {
  resumo: {
    idade: '55a, 5m e 17d',
    tempo_contribuicao: '33a, 2m e 4d',
    tempo_na_reforma: '29a, 8m e 12d',
    carencia: 398,
    media: '3651.92',
  },
  cartoes: [
    {
      id: 'tc_pedagio100',
      titulo: 'Aposentadoria por tempo — pedágio 100%',
      subtitulo: 'Regra de transição (EC 103/2019, art. 20).',
      elegivel: true,
      rmi: '3651.92',
      rmi_com_descartes: '3812.40',
      requisitos: [],
    },
    {
      id: 'tc_pontos',
      titulo: 'Aposentadoria por pontos',
      subtitulo: 'Regra de transição (EC 103/2019, art. 15).',
      elegivel: false,
      rmi: '2702.42',
      requisitos: [
        {
          nome: 'pontos',
          atual: '88,6',
          exigido: '102',
          faltou: '13,4 pontos',
        },
      ],
      previsao: '2033-02-10',
    },
    {
      id: 'invalidez_pos',
      titulo: 'Aposentadoria por incapacidade permanente',
      subtitulo: 'Pós-reforma.',
      elegivel: null,
      depende_de: 'incapacidade laborativa permanente',
      rmi: '2848.50',
      requisitos: [],
    },
  ],
  avisos: ['Tabelas de correção atualizadas até 09/2026.'],
};

const SIMULACAO = {
  mensal: '1825.96',
  perda_mensal: '1825.96',
  atrasados: '23737.48',
  atrasados_estimativa: { estimado: true, meses: 13 },
  honorario: {
    valor: '12599.12',
    percentual: 30,
    n_mensalidades: 3,
    tese: 'Auxílio-acidente (B36)',
  },
  motor: {
    rmi: '3651.92',
    rmi_com_descartes: '3812.40',
    memoria_calculo: {
      salarios: [
        {
          competencia: '07/1994',
          salario: '640.00',
          indice: '7,1834',
          corrigido: '4597.38',
        },
        {
          competencia: '08/1994',
          salario: '640.00',
          indice: '6,9112',
          corrigido: '4423.17',
        },
        {
          competencia: '09/1994',
          salario: '712.00',
          indice: '6,7020',
          corrigido: '4771.82',
        },
        {
          competencia: '10/1994',
          salario: '712.00',
          indice: '6,5501',
          corrigido: '4663.67',
        },
      ],
      soma: '1161482.10',
      divisor: 318,
      media: '3651.92',
    },
  },
  avisos: [
    'Risco de perda da qualidade de segurado (art. 27-A da Lei 8.213/91).',
    'Tabelas de correção atualizadas até 09/2026.',
  ],
};

const ELEGIBILIDADE = {
  qualidade: {
    cenarios: {
      sem_desemprego: {
        mantida: true,
        ate: '2027-03-15',
        fundamento: 'Período de graça de 12 meses após a última contribuição.',
      },
      com_desemprego: {
        mantida: false,
        ate: '2026-08-15',
        fundamento: 'Sem contribuição após o desligamento.',
      },
    },
  },
  carencia: {
    total: 398,
    art_27a: { aplicavel: true, exigencia_incapacidade: 6, cumprida: true },
  },
  lacunas: [
    {
      inicio: '2017-03-16',
      fim: '2017-12-31',
      meses: 9,
      graca_cobriu: true,
      ganho_tempo_meses: 9,
      ganho_carencia: 9,
    },
    {
      inicio: '2021-05-01',
      fim: '2021-10-31',
      meses: 6,
      graca_cobriu: false,
      ganho_tempo_meses: 6,
      ganho_carencia: 6,
    },
  ],
  decisoes_pendentes: [
    {
      tipo: 'desemprego',
      pergunta:
        'O segurado recebeu seguro-desemprego após sair da construtora?',
      efeito_por_resposta: {
        sim: 'período de graça amplia para 24 meses',
        nao: 'período de graça padrão de 12 meses',
      },
    },
  ],
  simulacao: [
    {
      cenario: 'Recolher a lacuna de 05/2021 a 10/2021',
      cartoes: [
        {
          id: 'tc_pontos',
          elegivel_antes: false,
          elegivel_depois: false,
          rmi_antes: '2702.42',
          rmi_depois: '2765.10',
          previsao_antes: '2033-02-10',
          previsao_depois: '2032-08-10',
        },
      ],
      aviso: 'Recolhimento em atraso exige comprovar a atividade no período.',
    },
  ],
  avisos: ['Qualidade de segurado estimada a partir do CNIS.'],
};

const PENSAO = {
  qualidade_falecido: {
    cenarios: {
      unico: {
        mantida: true,
        ate: '2027-06-15',
        fundamento: 'Em atividade na data do óbito.',
      },
    },
  },
  base: { valor: '3651.92', origem: 'média dos salários desde 07/1994' },
  percentual: 70,
  rmi: '2556.34',
  quotas: [
    {
      tipo: 'cônjuge',
      quota_pct: 50,
      cessa_em: {
        uniao_menor_2_anos: '2027-01-01',
        uniao_2_anos_ou_mais: null,
      },
      fundamento: 'Lei 13.135/2015 — duração pela idade do cônjuge.',
      avisos: [],
    },
    {
      tipo: 'filho',
      quota_pct: 50,
      cessa_em: '2031-05-10',
      fundamento: 'Até completar 21 anos.',
      avisos: ['Confirmar invalidez para prorrogação.'],
    },
  ],
  decisoes_pendentes: [
    {
      tipo: 'uniao_2_anos',
      pergunta: 'A união estável durou 2 anos ou mais até o óbito?',
      efeito_por_resposta: { sim: 'quota vitalícia', nao: 'quota de 4 meses' },
    },
  ],
  avisos: ['Confirme os dependentes com a família.'],
};

const MATERNIDADE = {
  rmi: '2245.80',
  carencia: { exigida: 0, fundamento: 'empregada: dispensada' },
  duracao_dias: 120,
  avisos: ['Valor igual à remuneração integral da empregada.'],
};

const PLANEJAMENTO = {
  data_calculo: '2026-10-05',
  cenarios: [
    {
      nome: 'conservador',
      salario: '1518.00',
      aliquota: 20,
      observacao: 'Contribuição sobre o salário mínimo.',
      resultados: [
        {
          regra: 'idade',
          titulo: 'Aposentadoria por idade',
          fecha_em: '2036-04-18',
          rmi_projetada: '1518.00',
          meses_contribuindo: 114,
          desembolso_total: '34610.40',
          payback_meses: 23,
        },
      ],
      regras_excluidas: [
        { regra: 'pontos', motivo: 'não atinge a pontuação mínima' },
      ],
      avisos: [],
    },
    {
      nome: 'otimizado',
      salario: '4200.00',
      aliquota: 20,
      observacao: 'Contribuição que maximiza a RMI no menor prazo.',
      resultados: [
        {
          regra: 'pedagio_100',
          titulo: 'Tempo — pedágio 100%',
          fecha_em: '2029-11-30',
          rmi_projetada: '3812.40',
          meses_contribuindo: 38,
          desembolso_total: '31920.00',
          payback_meses: 9,
        },
      ],
      regras_excluidas: [],
      avisos: ['Exige manter o recolhimento sem falhas até a data.'],
    },
  ],
  decisoes_pendentes: [
    {
      tipo: 'cenario_manter',
      pergunta: 'O segurado consegue manter R$ 840,00/mês de contribuição?',
    },
  ],
  avisos: ['Projeção com as regras vigentes em 10/2026.'],
};

const LIQUIDACAO = {
  total_principal_corrigido: '48213.77',
  total_juros: '9874.31',
  total_atualizacao_selic_ec136: '1204.55',
  total_geral: '59292.63',
  honorarios: {
    sucumbenciais: { valor: '5929.26' },
    contratuais: { valor: '17787.79' },
  },
  liquido_cliente: '41504.84',
  avisos: ['Correção pelo INPC até 11/2021 e SELIC depois (EC 113).'],
};

const HISTORICO = {
  payload: [
    {
      id: 31,
      segurado_nome: 'João Carlos Pereira',
      tipo: 'painel',
      der: '2026-09-30',
      created_at: '2026-10-05T09:40:00Z',
    },
    {
      id: 30,
      segurado_nome: 'Maria Aparecida Souza',
      tipo: 'honorario',
      der: '2025-11-12',
      created_at: '2026-10-04T16:15:00Z',
    },
    {
      id: 29,
      segurado_nome: 'Antônio Lima Ferreira',
      tipo: 'pensao',
      der: null,
      created_at: '2026-10-03T11:02:00Z',
    },
    {
      id: 28,
      segurado_nome: null,
      tipo: 'planejamento',
      der: null,
      created_at: '2026-10-02T14:27:00Z',
    },
  ],
};

const API = {
  'ramon_calculos/rascunho': RASCUNHO,
  calculos: HISTORICO,
  'leads/900/cnis': CNIS_DETALHE,
  'leads/900/painel': PAINEL,
  'leads/900/simulacao': SIMULACAO,
  'leads/900': {},
  'leads/900/elegibilidade': ELEGIBILIDADE,
  'leads/900/pensao': PENSAO,
  'leads/900/maternidade': MATERNIDADE,
  'leads/900/planejamento': PLANEJAMENTO,
  'leads/900/liquidacao': LIQUIDACAO,
  'leads/42': LEAD,
  'contacts/search': {
    payload: [
      { id: 5, name: 'João Carlos Pereira', phone_number: '+5548999123456' },
      { id: 6, name: 'João Pedro Martins', email: 'joaopedro@exemplo.com.br' },
    ],
  },
};

let respostas = API;
const responder = async url => {
  const path = url
    .replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '')
    .replace(/\?.*$/, '');
  return { data: respostas[path] ?? {} };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

// ---- roteiro de cliques: espera o seletor e age (preencher/clicar)
const esperar = sel =>
  new Promise(resolve => {
    const tick = () => {
      const el = document.querySelector(sel);
      if (el) resolve(el);
      else setTimeout(tick, 50);
    };
    tick();
  });
const preencher = async (sel, valor) => {
  const el = await esperar(sel);
  el.value = valor;
  el.dispatchEvent(new Event('input'));
  el.dispatchEvent(new Event('change'));
};
const clicar = async sel => (await esperar(sel)).click();
const roteiro =
  (comCnis, ...passos) =>
  () => {
    respostas = {
      ...API,
      'ramon_calculos/rascunho': comCnis ? RASCUNHO_CNIS : RASCUNHO,
    };
    setTimeout(async () => {
      // eslint-disable-next-line no-restricted-syntax
      for (const passo of passos) {
        // eslint-disable-next-line no-await-in-loop
        await passo();
      }
    }, 300);
  };
const der = () => preencher('[data-testid="sim-der"]', '2026-09-30');
const aba = nome => () => clicar(`[data-testid="sim-aba-${nome}"]`);
const clique = sel => () => clicar(`[data-testid="${sel}"]`);

const vazia = roteiro(false);
const possibilidades = roteiro(true, der, clique('sim-painel-run'));
const honorario = roteiro(
  true,
  der,
  aba('honorario'),
  clique('sim-run'),
  clique('sim-memoria-toggle')
);
const elegibilidade = roteiro(
  true,
  der,
  aba('elegibilidade'),
  clique('eleg-analisar')
);
const pensao = roteiro(
  true,
  aba('pensao'),
  () => preencher('[data-testid="pensao-data-obito"]', '2026-06-15'),
  () => preencher('[data-testid="pensao-valor-beneficio"]', ''),
  clique('pensao-calcular')
);
const maternidade = roteiro(
  true,
  aba('maternidade'),
  () => preencher('[data-testid="maternidade-data-evento"]', '2026-08-20'),
  clique('maternidade-calcular')
);
const planejamento = roteiro(
  true,
  aba('planejamento'),
  clique('planejamento-planejar')
);
const historico = roteiro(false, clique('calculos-historico-toggle'));
const cnis = roteiro(true, clique('sim-cnis-ajustes-toggle'));
const liquidacao = roteiro(
  true,
  der,
  clique('sim-painel-run'),
  clique('sim-cartao-liquidar-tc_pedagio100'),
  () => preencher('[data-testid="liq-dib"]', '2024-03-12'),
  () => preencher('[data-testid="liq-citacao"]', '2024-08-05'),
  clique('liq-run')
);
const busca = roteiro(false, clique('calculos-modo-busca'), () =>
  preencher('[data-testid="pessoa-search"]', 'João')
);
const lead = () => {
  respostas = API;
  route.params = { leadId: 42 };
};
</script>

<template>
  <Story title="Ramon/Cálculos" :layout="{ type: 'single', iframe: true }">
    <Variant title="Vazia" :init-state="vazia">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Possibilidades" :init-state="possibilidades">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Honorario" :init-state="honorario">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Elegibilidade" :init-state="elegibilidade">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Pensao" :init-state="pensao">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Maternidade" :init-state="maternidade">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Planejamento" :init-state="planejamento">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Historico" :init-state="historico">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="CNIS" :init-state="cnis">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Liquidacao" :init-state="liquidacao">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Busca" :init-state="busca">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
    <Variant title="Lead" :init-state="lead">
      <div class="flex min-h-screen"><Calculos /></div>
    </Variant>
  </Story>
</template>
