<script setup>
// Story da Agenda + Reuniões (aprovação visual por print, claro/escuro).
// Sem rede: window.axios responde por URL com dados fictícios; sem router: a
// rota de cada variante entra por provide; sem microfone: MediaRecorder e
// getUserMedia falsos levam o gravador ao estado "gravando".
import { h, provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Agenda from './Agenda.vue';
import Reunioes from './Reunioes.vue';

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

let respostas = API;
const responder = async url => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
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

const visao = v => () => {
  localStorage.setItem('ramon_agenda_view', v);
  localStorage.setItem('ramon_agenda_kind', 'all');
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
  </Story>
</template>
