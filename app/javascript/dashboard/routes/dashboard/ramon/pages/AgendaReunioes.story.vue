<script setup>
// Story da Agenda + Reuniões (aprovação visual por print, claro/escuro).
// Sem rede: window.axios responde por URL com dados fictícios; sem router: a
// rota de cada variante entra por provide; sem microfone: MediaRecorder e
// getUserMedia falsos levam o gravador ao estado "gravando". As variantes
// "A…" mostram as melhorias funcionais (janelas abertas por clique simulado).
import { h, provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import Agenda from './Agenda.vue';
import Reunioes from './Reunioes.vue';
import Esteira from './Esteira.vue';
import LeadNextAction from '../components/lead/LeadNextAction.vue';
import AgendaToday from '../components/command/AgendaToday.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import { TITULO } from '../helpers/ui';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
// segunda-feira desta semana às h:m, deslocada em `dia` dias
const segunda = new Date();
segunda.setHours(0, 0, 0, 0);
segunda.setDate(segunda.getDate() - ((segunda.getDay() + 6) % 7));
const semanaAs = (dia, hora, min = 0) => {
  const d = new Date(segunda.getTime() + dia * DIA);
  d.setHours(hora, min, 0, 0);
  return d.toISOString();
};
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();

const DONOS = [
  {
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    closer_id: 1,
    closer_name: 'Eduardo Schlata',
  },
  {
    sdr_id: 2,
    sdr_name: 'Gabriela Matos',
    closer_id: 3,
    closer_name: 'Lucas Pereira',
  },
  {
    sdr_id: 1,
    sdr_name: 'Eduardo Schlata',
    closer_id: null,
    closer_name: null,
  },
];
let id = 0;
const tarefa = (dia, hora, min, kind, title, leadName) => {
  id += 1;
  return {
    id,
    lead_id: id,
    user_id: 1,
    title,
    kind,
    due_at: semanaAs(dia, hora, min),
    completed_at: null,
    created_at: diasAtras(10),
    lead_name: leadName,
    ...DONOS[id % 3],
  };
};

const TAREFAS = [
  tarefa(0, 9, 0, 'meeting', 'Reunião de fechamento', 'Ana Paula Martins'),
  tarefa(0, 14, 30, 'task', 'Cobrar CNIS', 'Maria Aparecida Souza'),
  tarefa(
    1,
    10,
    0,
    'meeting',
    'Reunião Cal.com: Consulta inicial previdenciária',
    'José Ribeiro da Silva'
  ),
  tarefa(1, 16, 0, 'task', 'Retornar ligação', 'Carlos Eduardo Lima'),
  tarefa(2, 8, 30, 'task', 'Enviar contrato pelo ZapSign', 'Rosângela Vieira'),
  tarefa(
    2,
    11,
    0,
    'meeting',
    'Reunião Cal.com: Avaliação de auxílio-acidente',
    'João Carlos Pereira'
  ),
  tarefa(2, 15, 0, 'task', 'Pedir laudo do ortopedista', 'Sebastião Nunes'),
  tarefa(2, 17, 30, 'meeting', 'Reunião de documentos', 'Luciana Freitas'),
  tarefa(3, 9, 30, 'meeting', 'Assinatura presencial', 'Antônio Becker'),
  tarefa(4, 13, 0, 'task', 'Follow-up: proposta enviada', 'Patrícia Zanella'),
  tarefa(
    4,
    15,
    30,
    'meeting',
    'Reunião Cal.com: Revisão da vida toda',
    'Valdir Tomasi'
  ),
  tarefa(7, 10, 0, 'meeting', 'Reunião de fechamento', 'Irene Bortolotto'),
  tarefa(9, 14, 0, 'task', 'Cobrar CTPS digital', 'Marcos Antunes'),
  tarefa(-3, 9, 0, 'task', 'Conferir PPP', 'Elisa Cardoso'),
  tarefa(-5, 15, 0, 'meeting', 'Reunião de documentos', 'Marcos Antunes'),
  // concluída: não aparece na Agenda
  {
    ...tarefa(0, 11, 0, 'task', 'Ligar para o INSS', 'Ana Paula Martins'),
    completed_at: diasAtras(0),
  },
];

const ATA = `## Resumo
Cliente relatou acidente de trajeto em 2022 com fratura no punho direito; segue trabalhando como pedreiro, com dor ao carregar peso.

## Decisões
- Honorário de 30% dos atrasados + 3 benefícios explicado e aceito.
- Contrato enviado pelo ZapSign no fim da reunião.

## Próximos passos
- Cliente traz o laudo do ortopedista até sexta.
- Escritório pede o CNIS atualizado no Meu INSS.`;

const TRANSCRICAO =
  'Eduardo: Bom dia, seu João. Pode me contar como foi o acidente?\nJoão: Foi em março de 2022, indo pro serviço de moto. Quebrei o punho e fiquei quarenta dias afastado.\nEduardo: E hoje, o punho incomoda no trabalho?\nJoão: Incomoda, doutor. Carregar saco de cimento eu já não consigo como antes.';

const REUNIOES = [
  {
    id: 1,
    titulo: 'Reunião de fechamento — João Carlos Pereira',
    status: 'pronta',
    duracao_segundos: 2280,
    created_at: diasAtras(1),
    user_name: 'Eduardo Schlata',
    lead_id: 7,
    lead_name: 'João Carlos Pereira',
  },
  {
    id: 2,
    titulo: 'Atendimento presencial — Maria Aparecida',
    status: 'transcrevendo',
    duracao_segundos: 1460,
    created_at: diasAtras(0.02),
    user_name: 'Gabriela Matos',
    lead_id: 8,
    lead_name: 'Maria Aparecida Souza',
  },
  {
    id: 3,
    titulo: 'Reunião de documentos — Sebastião Nunes',
    status: 'erro',
    duracao_segundos: 610,
    created_at: diasAtras(2),
    user_name: 'Eduardo Schlata',
    lead_id: null,
    lead_name: null,
  },
  {
    id: 4,
    titulo: 'Consulta inicial — Rosângela Vieira',
    status: 'pronta',
    duracao_segundos: 1830,
    created_at: diasAtras(4),
    user_name: 'Gabriela Matos',
    lead_id: 9,
    lead_name: 'Rosângela Vieira',
  },
];

const AUDIO = 'data:audio/webm;base64,GkXfo0AgQoaBAUL3gQFC8oEEQvOBCA==';
const API = {
  lead_tasks: { payload: TAREFAS },
  ramon_reunioes: { payload: REUNIOES },
  'ramon_reunioes/1': {
    ...REUNIOES[0],
    ata: ATA,
    transcricao: TRANSCRICAO,
    erro: null,
    audio_url: AUDIO,
  },
  'ramon_reunioes/2': {
    ...REUNIOES[1],
    ata: null,
    transcricao: null,
    erro: null,
    audio_url: AUDIO,
  },
  'ramon_reunioes/3': {
    ...REUNIOES[2],
    ata: null,
    transcricao: null,
    erro: 'Falha na transcrição: o serviço de áudio não respondeu (timeout).',
    audio_url: AUDIO,
  },
};

// Painel do lead (LeadNextAction): reunião do Cal.com do lead 7, Closer = eu
const REUNIAO_PAINEL = {
  id: 70,
  lead_id: 7,
  user_id: null,
  title: 'Reunião Cal.com: Primeiro Atendimento',
  kind: 'meeting',
  due_at: semanaAs(2, 14, 0),
  completed_at: null,
  lead_name: 'João Carlos Pereira',
  sdr_id: 2,
  sdr_name: 'Gabriela Matos',
  closer_id: 1,
  closer_name: 'Eduardo Schlata',
};
API['leads/7/tasks'] = { payload: [REUNIAO_PAINEL] };
// busca de pessoa da janela "Vincular a um lead"
API['contacts/search'] = {
  payload: [
    { id: 31, name: 'Sebastião Nunes', phone_number: '+5548991230001' },
    { id: 32, name: 'Sebastiana Prado', phone_number: '+5548991230002' },
  ],
};
API.leads = {
  payload: [
    {
      id: 21,
      name: 'Sebastião — Auxílio-acidente',
      thesis_name: 'Auxílio-acidente',
    },
    {
      id: 22,
      name: 'Sebastião — Revisão',
      thesis_name: 'Revisão da vida toda',
    },
  ],
};
// Esteira com o item de reunião no topo (Remarcar no lead em vez de Adiar)
API.theses = [];
API.ramon_esteira = {
  board: { done_today: 2 },
  items: [
    {
      lead_id: 7,
      name: 'João Carlos Pereira',
      value: 38400,
      stage_name: 'Reunião agendada',
      suggested_action: 'task',
      conversation_id: 101,
      task_id: 70,
      task_kind: 'meeting',
      reasons: [
        { key: 'TASK_OVERDUE', params: { title: 'Reunião de fechamento' } },
      ],
    },
    {
      lead_id: 2,
      name: 'José Ribeiro da Silva',
      value: 12000,
      task_id: 12,
      task_kind: 'follow_up',
      suggested_action: 'follow_up',
      reasons: [{ key: 'STALLED', params: { days: 5 } }],
    },
  ],
};

let respostas = API;
const responder = async (url, config) => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '').split('?')[0];
  const q = config?.params?.q?.toLowerCase();
  if (path === 'ramon_reunioes' && q) {
    const achou = r => `${r.titulo} ${r.lead_name || ''}`.toLowerCase();
    return { data: { payload: REUNIOES.filter(r => achou(r).includes(q)) } };
  }
  return { data: respostas[path] ?? {} };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

// gravador sem microfone: grava "de mentira" para o print do estado gravando
class GravadorFalso {
  // eslint-disable-next-line class-methods-use-this
  start() {}

  // eslint-disable-next-line class-methods-use-this
  pause() {}
}
GravadorFalso.isTypeSupported = () => true;

const store = useStore();
store.registerModule('route', { state: { params: { accountId: 1 } } });
// agente (não gestor): a Agenda abre em "Minhas"
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  name: 'Eduardo Schlata',
  accounts: [{ id: 1, role: 'agent' }],
});

// clique/digitação simulados depois da montagem (janelas abertas no print)
const clicar =
  (seletor, ms = 1500) =>
  () =>
    setTimeout(() => document.querySelector(seletor)?.click(), ms);
const digitar = (seletor, texto, ms) =>
  setTimeout(() => {
    const campo = document.querySelector(seletor);
    if (!campo) return;
    campo.value = texto;
    campo.dispatchEvent(new Event('input'));
  }, ms);
const buscarReunioes = () =>
  digitar('[data-testid="reunioes-busca"]', 'sebast', 1200);
const vincularLead = () => {
  clicar('[data-testid="reuniao-vincular"]', 1200)();
  digitar('[data-testid="reuniao-vincular-busca"]', 'Sebast', 1800);
  clicar('[data-testid="reuniao-vincular-pessoa"]', 3000)();
};

// Centro "Hoje na agenda": vencida fixada, feita apagada, a próxima em azul
const hojeAs = (hora, min = 0) => {
  const d = new Date();
  d.setHours(hora, min, 0, 0);
  return d.toISOString();
};
const AGENDA_HOJE = [
  {
    id: 1,
    lead_id: 8,
    lead_name: 'Marcos Antunes',
    title: 'Reunião de documentos',
    due_at: diasAtras(3),
    user_name: 'Eduardo Schlata',
    source: 'Indicação',
    vencida: true,
  },
  {
    id: 2,
    lead_id: 3,
    lead_name: 'Ana Paula Martins',
    title: 'Reunião de fechamento',
    due_at: hojeAs(0, 5),
    user_name: 'Eduardo Schlata',
    source: 'Meta Ads',
    completed_at: hojeAs(0, 40),
  },
  {
    id: 3,
    lead_id: 4,
    lead_name: 'José Ribeiro da Silva',
    title: 'Reunião Cal.com: Consulta inicial',
    due_at: hojeAs(23, 50),
    user_name: 'Lucas Pereira',
    source: 'calcom-agenda',
  },
];

const visao = v => () => {
  localStorage.setItem('ramon_agenda_view', v);
  localStorage.setItem('ramon_agenda_kind', 'all');
};
const dono = valor => () => {
  visao('week')();
  localStorage.setItem('ramon_agenda_owner', valor);
};
const diaDoTime = () => {
  visao('day')();
  localStorage.setItem('ramon_agenda_owner', 'team');
};
const vazia = () => {
  visao('week')();
  respostas = { ...API, lead_tasks: { payload: [] } };
};
const gravando = () => {
  window.MediaRecorder = GravadorFalso;
  Object.defineProperty(navigator, 'mediaDevices', {
    value: { getUserMedia: async () => ({ getTracks: () => [] }) },
  });
  setTimeout(
    () => document.querySelector('[data-testid="recorder-start"]')?.click(),
    1500
  );
};

const ComRota = {
  props: { params: { type: Object, required: true } },
  setup(props, { slots }) {
    provide(
      routeLocationKey,
      reactive({ params: { accountId: 1, ...props.params }, query: {} })
    );
    provide(routerKey, { push: () => {}, resolve: () => ({ href: '#' }) });
    return () => h('div', { class: 'h-screen' }, slots.default?.());
  },
};
</script>

<template>
  <Story
    title="Ramon/Agenda e Reuniões"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Agenda" :init-state="visao('week')">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="Agenda vazia" :init-state="vazia">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="Agenda dia" :init-state="visao('day')">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="Agenda mes" :init-state="visao('month')">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="Reunioes">
      <ComRota :params="{}"><Reunioes /></ComRota>
    </Variant>
    <Variant title="Reuniao ata">
      <ComRota :params="{ reuniaoId: 1 }"><Reunioes /></ComRota>
    </Variant>
    <Variant title="Reuniao processando">
      <ComRota :params="{ reuniaoId: 2 }"><Reunioes /></ComRota>
    </Variant>
    <Variant title="Reuniao erro">
      <ComRota :params="{ reuniaoId: 3 }"><Reunioes /></ComRota>
    </Variant>
    <Variant title="Gravador gravando" :init-state="gravando">
      <ComRota :params="{}"><Reunioes /></ComRota>
    </Variant>

    <!-- Melhorias funcionais (A1–A8) -->
    <Variant
      title="A1 Remarcar"
      :init-state="clicar('[data-testid=&quot;next-action-remarcar&quot;]')"
    >
      <ComRota :params="{}">
        <div class="w-[340px] mx-auto pt-10">
          <LeadNextAction :lead-id="7" />
        </div>
      </ComRota>
    </Variant>
    <Variant title="A1 Esteira">
      <ComRota :params="{}"><Esteira /></ComRota>
    </Variant>
    <Variant
      title="A2 Cancelar"
      :init-state="clicar('[data-testid=&quot;next-action-cancelar&quot;]')"
    >
      <ComRota :params="{}">
        <div class="w-[340px] mx-auto pt-10">
          <LeadNextAction :lead-id="7" />
        </div>
      </ComRota>
    </Variant>
    <Variant title="A2 Reuniao aberta">
      <div class="h-screen bg-n-background">
        <ConfirmModal
          :title="$t('RAMON.TASKS.MEETING_CONFLICT_TITLE')"
          :message="
            $t('RAMON.TASKS.MEETING_CONFLICT', { quando: '08/10, 14:00' })
          "
          :confirm-label="$t('RAMON.TASKS.MEETING_CONFLICT_CONFIRM')"
          confirm-color="blue"
        />
      </div>
    </Variant>
    <Variant
      title="A3 Como foi"
      :init-state="clicar('[data-testid=&quot;next-action-done&quot;]')"
    >
      <ComRota :params="{}">
        <div class="w-[340px] mx-auto pt-10">
          <LeadNextAction :lead-id="7" />
        </div>
      </ComRota>
    </Variant>
    <Variant title="A4 Agenda minhas" :init-state="dono('mine')">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="A4 Agenda time" :init-state="dono('team')">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="A8 Agenda dia" :init-state="diaDoTime">
      <ComRota :params="{}"><Agenda /></ComRota>
    </Variant>
    <Variant title="A8 Centro hoje">
      <div class="h-screen p-8 bg-n-background">
        <div class="w-[420px] mx-auto">
          <h2 :class="TITULO" class="mb-2.5">
            {{ $t('RAMON.COMMAND.AGENDA.TITLE') }}
          </h2>
          <AgendaToday :items="AGENDA_HOJE" />
        </div>
      </div>
    </Variant>
    <Variant title="A6 Reunioes busca" :init-state="buscarReunioes">
      <ComRota :params="{}"><Reunioes /></ComRota>
    </Variant>
    <Variant title="A6 Reunioes lista">
      <ComRota :params="{}"><Reunioes /></ComRota>
    </Variant>
    <Variant title="A6 Reuniao lead">
      <ComRota :params="{ reuniaoId: 1 }"><Reunioes /></ComRota>
    </Variant>
    <Variant title="A6 Vincular" :init-state="vincularLead">
      <ComRota :params="{ reuniaoId: 3 }"><Reunioes /></ComRota>
    </Variant>
  </Story>
</template>
