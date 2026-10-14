<script setup>
// Story das telas do roteiro da IA (F2) — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS por URL. Os textos são exemplo de tela,
// não o conteúdo dos roteiros (esse entra na F4, com o aprovado do Eduardo).
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Playbooks from './Playbooks.vue';
import RoteiroDoLead from '../components/lead/RoteiroDoLead.vue';
import { SELECT, CARTAO } from '../helpers/ui';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const TESE = {
  id: 1,
  name: 'Auxílio-acidente (exemplo)',
  area: 'previdenciario',
  active: true,
  position: 0,
  palavras_chave: ['acidente', 'sequela'],
  items: [],
};
const passo = (id, thesisId, position, chave, titulo, extra = {}) => ({
  id,
  thesis_id: thesisId,
  position,
  chave,
  titulo,
  orientacao: '',
  tipo_resposta: 'sim_nao',
  opcoes: [],
  calculadora: null,
  calculadora_campos: {},
  saidas: [],
  edited: true,
  ...extra,
});
const PASSOS = [
  passo(1, null, 0, 'tem_advogado', 'Já tem advogado no caso', {
    saidas: [
      {
        id: 'sim',
        quando: 'sim',
        acao: 'desqualificar',
        motivo: 'tem advogado',
        motivo_perda: 'Outro',
        efeitos: { etiqueta: 'TemAdvogado' },
      },
      { id: 'nao', quando: 'nao', acao: 'seguir' },
    ],
  }),
  passo(2, 1, 0, 'recebeu_auxilio', 'Recebeu auxílio-doença pelo acidente', {
    orientacao: '(exemplo) Pergunte se ficou afastado recebendo do INSS.',
    saidas: [
      { id: 'sim', quando: 'sim', acao: 'ir_para', alvo: 'sequela' },
      { id: 'nao', quando: 'nao', acao: 'seguir' },
    ],
  }),
  passo(3, 1, 1, 'data_acidente', 'Data do acidente', {
    tipo_resposta: 'data',
  }),
  passo(4, 1, 2, 'graca', 'Último emprego com carteira', {
    tipo_resposta: 'data',
    calculadora: 'periodo_de_graca',
    calculadora_campos: { ultimo_vinculo: 'graca', evento: 'data_acidente' },
    saidas: [
      { id: 's1', quando: 'dentro', acao: 'seguir' },
      {
        id: 's2',
        quando: 'fora',
        acao: 'desqualificar',
        motivo: 'fora do período de graça',
      },
      { id: 's3', quando: '*', acao: 'humano', motivo: 'graça depende' },
    ],
  }),
  passo(5, 1, 3, 'sequela', 'Ficou sequela', {
    tipo_resposta: 'texto',
    saidas: [
      {
        id: 's1',
        quando: 'ficou alguma limitação',
        acao: 'concluir',
        efeitos: { etapa: 'Qualificação' },
      },
      {
        id: 's2',
        quando: 'voltou 100%',
        acao: 'desqualificar',
        motivo: 'sem sequela',
      },
    ],
  }),
];
const CALCULADORAS = {
  periodo_de_graca: {
    campos: [
      'ultimo_vinculo',
      'evento',
      'mais_de_120',
      'desemprego',
      'facultativa',
    ],
    resultados: ['dentro', 'fora', 'depende'],
  },
  renda_per_capita: {
    campos: ['renda_total', 'moradores'],
    resultados: ['abaixo', 'acima', 'depende'],
  },
  prescricao_5_anos: {
    campos: ['data'],
    resultados: ['dentro', 'ultimo_ano', 'prescrito', 'depende'],
  },
  meses_ate_65: {
    campos: ['nascimento'],
    resultados: ['ja_tem_65', 'menos_de_65', 'depende'],
  },
  data_prevista_parto: {
    campos: ['semanas'],
    resultados: ['ja_pode_pedir', 'aguardar', 'depende'],
  },
  prazo_inss: {
    campos: ['requerimento', 'pericia'],
    resultados: ['aguardar', 'forcar_julgamento', 'depende'],
  },
};
const API = {
  lead_config: {
    stages: [
      { id: 1, name: 'Novo', position: 0, is_won: false, is_lost: false },
      {
        id: 2,
        name: 'Qualificação',
        position: 1,
        is_won: false,
        is_lost: false,
      },
      { id: 9, name: 'Perdido', position: 9, is_won: false, is_lost: true },
    ],
    lost_reasons: [
      { id: 1, name: 'Sem viabilidade' },
      { id: 2, name: 'Outro' },
    ],
  },
  theses: [TESE],
  'theses/1': TESE,
  roteiro_passos: { payload: PASSOS, calculadoras: CALCULADORAS },
};
const caminho = url => url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
const responder = async url => ({ data: API[caminho(url)] ?? {} });
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

const clicar = (testid, n = 0) =>
  document.querySelectorAll(`[data-testid="${testid}"]`)[n]?.click();
const abrirRoteiro = then => () =>
  setTimeout(() => {
    clicar('playbooks-item');
    setTimeout(() => {
      clicar('playbooks-aba-roteiro');
      if (then) setTimeout(then, 300);
    }, 400);
  }, 1200);
const roteiroDaTese = abrirRoteiro();
// índice 3 = 1 passo comum + 3º passo da tese (Último emprego com carteira)
const passoAberto = abrirRoteiro(() => clicar('roteiro-passo-abrir', 3));

const linha = (chave, titulo, situacao, extra = {}) => ({
  chave,
  titulo,
  comum: false,
  situacao,
  valor: null,
  saida: null,
  calc: null,
  ...extra,
});
const PAINEL_ANDAMENTO = {
  desfecho: null,
  motivo: null,
  decisivo: null,
  aguarda_equipe: false,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'Já tem advogado no caso', 'respondido', {
      comum: true,
      valor: 'nao',
    }),
    linha(
      'recebeu_auxilio',
      'Recebeu auxílio-doença pelo acidente',
      'respondido',
      { valor: 'nao' }
    ),
    linha('data_acidente', 'Data do acidente', 'respondido', {
      valor: '2026-01-10',
    }),
    linha('graca', 'Último emprego com carteira', 'atual'),
    linha('sequela', 'Ficou sequela', 'pendente'),
  ],
};
const PAINEL_DESQUALIFICADO = {
  desfecho: 'desqualificado',
  motivo: 'fora do período de graça',
  decisivo: 'graca',
  aguarda_equipe: true,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'Já tem advogado no caso', 'respondido', {
      comum: true,
      valor: 'nao',
    }),
    linha(
      'recebeu_auxilio',
      'Recebeu auxílio-doença pelo acidente',
      'respondido',
      { valor: 'nao' }
    ),
    linha('data_acidente', 'Data do acidente', 'respondido', {
      valor: '2026-01-10',
    }),
    linha('graca', 'Último emprego com carteira', 'respondido', {
      valor: '2022-01-01',
      calc: { resultado: 'fora', detalhe: 'mais de 36 meses sem contribuir' },
    }),
    linha('sequela', 'Ficou sequela', 'fora'),
  ],
};
</script>

<template>
  <Story title="Ramon/Roteiro da IA" :layout="{ type: 'single' }">
    <Variant title="Passos comuns">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Roteiro da tese" :init-state="roteiroDaTese">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Passo aberto" :init-state="passoAberto">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Painel em andamento">
      <div class="h-screen bg-n-background py-6">
        <div class="mx-auto w-[400px]">
          <RoteiroDoLead :roteiro="PAINEL_ANDAMENTO" :lead-id="42" />
        </div>
      </div>
    </Variant>
    <Variant title="Painel desqualificado">
      <div class="h-screen bg-n-background py-6">
        <div class="mx-auto w-[400px]">
          <RoteiroDoLead :roteiro="PAINEL_DESQUALIFICADO" :lead-id="42" />
        </div>
      </div>
    </Variant>
    <Variant title="Testar com tese">
      <div class="h-screen bg-n-background p-6">
        <div class="flex flex-wrap items-start gap-3">
          <select class="!w-60 shrink-0" :class="SELECT">
            <option value="">Sem tese (exemplo)</option>
            <option value="1" selected>{{ TESE.name }}</option>
          </select>
        </div>
        <div class="mt-3 flex gap-3">
          <div :class="CARTAO" class="flex-1 min-w-0 text-sm text-n-slate-11">
            <p class="mb-2">
              <b>Você:</b> (exemplo fictício) Sofri um acidente de moto.
            </p>
            <p>
              <b>Assistente:</b> (exemplo fictício) Você já tem advogado no
              caso?
            </p>
          </div>
          <RoteiroDoLead
            class="w-72 shrink-0 self-start"
            :roteiro="PAINEL_ANDAMENTO"
          />
        </div>
      </div>
    </Variant>
  </Story>
</template>
