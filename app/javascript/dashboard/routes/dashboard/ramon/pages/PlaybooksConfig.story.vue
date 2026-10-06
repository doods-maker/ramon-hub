<script setup>
// Story de Playbooks + Configurações do Funil — aprovação visual por print,
// claro/escuro. Sem rede: window.axios responde com dados FICTÍCIOS por URL.
// As variantes que abrem tese/modal clicam pelo data-testid depois de montar
// (serve no código antigo e no novo).
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Playbooks from './Playbooks.vue';
import FunilConfig from './FunilConfig.vue';
import LeadPlaybook from '../components/conversation/LeadPlaybook.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

// Padrão da banca em todas as teses: 30% dos atrasados + 3 benefícios.
const HONORARIO = { honorario_percentual: 30, honorario_n_mensalidades: 3 };

const ITENS_ACIDENTE = [
  {
    id: 101,
    section: 'abertura',
    position: 1,
    title: 'Primeiro contato',
    content:
      'Olá {{nome}}, aqui é do escritório Ramon Antonio Advogados. Vi que você teve um acidente e ficou com sequela. Posso te fazer umas perguntas rápidas pra ver se cabe o auxílio-acidente?',
  },
  {
    id: 102,
    section: 'abertura',
    position: 2,
    title: 'Sem resposta em 24h',
    content:
      'Oi! Passando pra saber se conseguiu ver a mensagem de ontem. Quando puder, me responde que eu te explico como funciona.',
  },
  {
    id: 103,
    section: 'qualificacao',
    position: 1,
    title: 'Sequela e vínculo',
    content:
      'O acidente aconteceu quando você tinha carteira assinada? Ficou alguma limitação no movimento ou na força?',
  },
  {
    id: 104,
    section: 'objecao',
    position: 1,
    title: '"Já recebi auxílio-doença"',
    content:
      'Faz sentido a dúvida. O auxílio-doença paga enquanto você está afastado; o auxílio-acidente é outro benefício, pago depois da alta, quando fica sequela. Um não impede o outro.',
  },
  {
    id: 105,
    section: 'objecao',
    position: 2,
    title: '"Vou continuar trabalhando?"',
    content:
      'Sim. O auxílio-acidente é pago junto com o salário — você continua trabalhando normalmente.',
  },
  {
    id: 106,
    section: 'documento',
    position: 1,
    title: 'Lista básica',
    content:
      'RG e CPF, comprovante de residência, CAT (se tiver), laudos e exames do acidente e a carta de alta do INSS.',
  },
  {
    id: 107,
    section: 'roteiro',
    position: 1,
    title: 'Reunião de fechamento',
    content:
      '1) Resumo do caso  2) O que o INSS costuma alegar  3) Honorário: 30% dos atrasados + 3 benefícios  4) Próximo passo: assinatura e documentos.',
  },
];

const TESES = [
  {
    id: 1,
    position: 1,
    name: 'Auxílio-acidente',
    description:
      'Sequela permanente após acidente (de trabalho ou não) que reduz a capacidade para o trabalho habitual.',
    area: 'Previdenciário',
    active: true,
    ...HONORARIO,
  },
  {
    id: 2,
    position: 2,
    name: 'BPC/LOAS',
    description:
      'Benefício assistencial ao idoso (65+) ou à pessoa com deficiência de baixa renda.',
    area: 'Assistencial',
    active: true,
    ...HONORARIO,
  },
  {
    id: 3,
    position: 3,
    name: 'Aposentadoria especial',
    description:
      'Tempo de trabalho exposto a agentes nocivos (ruído, químicos, eletricidade) comprovado por PPP.',
    area: 'Previdenciário',
    active: true,
    ...HONORARIO,
  },
  {
    id: 4,
    position: 4,
    name: 'Trabalhista',
    description: 'Verbas rescisórias, horas extras e insalubridade.',
    area: 'Trabalhista',
    active: true,
    ...HONORARIO,
  },
  {
    id: 5,
    position: 5,
    name: 'Revisão da vida toda',
    description: 'Tese encerrada pelo STF — mantida só para consulta.',
    area: 'Previdenciário',
    active: false,
    ...HONORARIO,
  },
];

const ETAPAS = [
  {
    id: 1,
    position: 1,
    name: 'Novo lead',
    label: 'fase-novo',
    color: '#3b82f6',
    probability: 5,
    stalled_after_days: 1,
    sla_minutes: 15,
  },
  {
    id: 2,
    position: 2,
    name: 'Qualificação',
    label: 'fase-qualificacao',
    automacao: true,
    color: '#06b6d4',
    probability: 20,
    stalled_after_days: 3,
  },
  {
    id: 3,
    position: 3,
    name: 'Aguardando documentos',
    label: 'fase-aguardando-documentos',
    color: '#f59e0b',
    probability: 40,
    stalled_after_days: 5,
  },
  {
    id: 4,
    position: 4,
    name: 'Reunião marcada',
    label: 'fase-reuniao-agendada',
    automacao: true,
    nome_cliente: 'Reunião com o advogado marcada',
    color: '#14b8a6',
    probability: 60,
    stalled_after_days: 2,
  },
  {
    id: 5,
    position: 5,
    name: 'Proposta enviada',
    label: 'fase-negociacao',
    color: '#ec4899',
    probability: 75,
    stalled_after_days: 4,
  },
  {
    id: 6,
    position: 6,
    name: 'Contrato assinado',
    label: 'fase-fechado',
    color: '#22c55e',
    probability: 100,
    stalled_after_days: null,
    is_won: true,
  },
  {
    id: 7,
    position: 7,
    name: 'Perdido',
    label: 'fase-perdido',
    color: null,
    probability: 0,
    stalled_after_days: null,
    is_lost: true,
  },
];

const LEAD_CONFIG = {
  stages: ETAPAS,
  benefit_types: [
    { id: 1, name: 'Auxílio-acidente' },
    { id: 2, name: 'BPC/LOAS — deficiência' },
    { id: 3, name: 'BPC/LOAS — idoso' },
    { id: 4, name: 'Aposentadoria especial' },
    { id: 5, name: 'Aposentadoria por idade' },
    { id: 6, name: 'Auxílio por incapacidade temporária' },
  ],
  priorities: [
    { id: 1, name: 'Urgente (prescrição)', weight: 10 },
    { id: 2, name: 'Alta', weight: 5 },
    { id: 3, name: 'Normal', weight: 1 },
  ],
};

const API = {
  theses: TESES,
  'theses/1': { ...TESES[0], items: ITENS_ACIDENTE },
  'theses/2': { ...TESES[1], items: [] },
  lead_config: LEAD_CONFIG,
};

// Tese criada pela tela: nasce com o honorário padrão (30% + 3).
const TESE_NOVA = {
  id: 6,
  position: 6,
  name: 'Revisão do teto',
  description: null,
  area: null,
  active: true,
  ...HONORARIO,
};
const POST = { theses: TESE_NOVA };
API['theses/6'] = { ...TESE_NOVA, items: [] };

let falhar = false;
const caminho = url => url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
const responder = async url => {
  if (falhar) throw new Error('offline');
  return { data: API[caminho(url)] ?? {} };
};
// Tese com leads: o servidor recusa a exclusão (422 + leads_count).
const excluir = async url => {
  if (caminho(url) === 'theses/2') {
    throw Object.assign(new Error('422'), {
      response: {
        status: 422,
        data: {
          error: '12 leads usam esta tese — desative em vez de excluir',
          leads_count: 12,
        },
      },
    });
  }
  return { data: {} };
};
window.axios = {
  get: responder,
  post: async url => ({ data: POST[caminho(url)] ?? API[caminho(url)] ?? {} }),
  patch: responder,
  put: responder,
  delete: excluir,
};

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });

// Lead fictício na etapa "Reunião marcada" (label fase-reuniao-agendada).
const LEAD = {
  id: 41,
  name: 'Maria Aparecida Souza',
  contact_name: 'Maria Aparecida Souza',
  thesis_id: 1,
  lead_stage_id: 4,
};
const scriptsDoLead = () => {
  store.dispatch('leadConfig/get');
  store.dispatch('theses/get');
};

const clicar = (testid, n = 0) =>
  document.querySelectorAll(`[data-testid="${testid}"]`)[n]?.click();
const depois = (ms, fn) => () => setTimeout(fn, ms);

const aberta = depois(1200, () => clicar('playbooks-item'));
const editando = depois(1200, () => {
  clicar('playbooks-item');
  setTimeout(() => {
    const campo = document.querySelectorAll(
      '[data-testid="playbooks-item-content-input"]'
    )[2];
    campo?.focus();
  }, 600);
});
const removerTese = depois(1200, () => clicar('playbooks-item-remove', 1));
const removerBeneficio = depois(1200, () => clicar('benefit-remove', 1));
const teseEmUso = depois(1200, () => {
  clicar('playbooks-item-remove', 1);
  setTimeout(() => clicar('confirm-modal-confirm'), 400);
});
const teseNova = depois(1200, () => {
  const campo = document.querySelector('[data-testid="playbooks-add-input"]');
  campo.value = 'Revisão do teto';
  campo.dispatchEvent(new Event('input'));
  setTimeout(() => clicar('playbooks-add-button'), 200);
});
const erro = () => {
  falhar = true;
};
</script>

<template>
  <Story title="Ramon/Playbooks e Funil" :layout="{ type: 'single' }">
    <Variant title="Playbooks">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Tese aberta" :init-state="aberta">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Editar roteiro" :init-state="editando">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Remover tese" :init-state="removerTese">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Tese em uso" :init-state="teseEmUso">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Tese nova" :init-state="teseNova">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Scripts do lead" :init-state="scriptsDoLead">
      <div class="h-screen overflow-y-auto bg-n-background py-6">
        <div class="mx-auto w-[400px]"><LeadPlaybook :lead="LEAD" /></div>
      </div>
    </Variant>
    <Variant title="Funil">
      <div class="h-screen"><FunilConfig /></div>
    </Variant>
    <Variant title="Funil remover" :init-state="removerBeneficio">
      <div class="h-screen"><FunilConfig /></div>
    </Variant>
    <Variant title="Funil erro" :init-state="erro">
      <div class="h-screen"><FunilConfig /></div>
    </Variant>
  </Story>
</template>
