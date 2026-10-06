<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { onKeyStroke, onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadFields from './LeadFields.vue';
import LeadNextAction from './LeadNextAction.vue';
import MiniEsteira from './MiniEsteira.vue';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import LeadNotes from './LeadNotes.vue';
import LeadReuniao from './LeadReuniao.vue';
import LeadQuizResumo from './LeadQuizResumo.vue';
import LeadZapsignCard from './LeadZapsignCard.vue';
import LostReasonModal from '../kanban/LostReasonModal.vue';
import ConfirmModal from '../ConfirmModal.vue';
import LeadCopilot from '../conversation/LeadCopilot.vue';
import LeadHistory from '../conversation/LeadHistory.vue';
import LeadSugerirResposta from '../conversation/LeadSugerirResposta.vue';
import LeadPlaybook from '../conversation/LeadPlaybook.vue';
import LeadSimulador from '../conversation/LeadSimulador.vue';
import DocChecklist from './DocChecklist.vue';
import ArquivosRecebidos from './ArquivosRecebidos.vue';
import QualificacaoViva from './QualificacaoViva.vue';
import { useLeadPanelTabs } from '../../composables/useLeadPanelSections';
import { useTemperatura } from '../../composables/useTemperatura';
import { prescriptionInfo } from '../../helpers/prescription';
import { formatBrl, parseBrlInput } from '../../helpers/currency';
import { waMeUrl, formatPhoneBr } from '../../helpers/phone';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { dynamicTime } from 'shared/helpers/timeHelper';
import LeadsAPI from 'dashboard/api/leads';
import RodarFluxo from 'dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue';
import {
  CARTAO,
  CARTAO_STATUS,
  FILETE,
  SECAO,
  TITULO,
  CAMPO,
  NAV_ICONE,
  NAV_ICONE_ATIVO,
  NAV_ICONE_INATIVO,
  CHIP,
  TOM,
  LINHA,
  MENU,
  CAMPO_GRANDE,
  SELECT_GRANDE,
} from '../../helpers/ui';

const props = defineProps({
  lead: { type: Object, required: true },
  context: {
    type: String,
    default: 'conversation',
    validator: v => ['conversation', 'drawer'].includes(v),
  },
  conversationId: { type: [Number, String], default: null },
});
const emit = defineEmits(['discarded', 'openConversation', 'navigate']);

defineOptions({ name: 'LeadPanelBody' });
const store = useStore();
const { t } = useI18n();
const stages = useMapGetter('leadConfig/getStages');
const channels = useMapGetter('leadConfig/getChannels');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
const benefitTypes = useMapGetter('leadConfig/getBenefitTypes');
const theses = useMapGetter('theses/getTheses');

// Etapas/motivos só eram buscados pelo Funil: abrir a conversa direto (F5)
// deixava o chip de etapa VAZIO e o modal de perda sem motivos.
onMounted(() => {
  if (!stages.value?.length) store.dispatch('leadConfig/get');
});

const inConversation = computed(() => props.context === 'conversation');

// ----- identidade: foto do contato (remetente da conversa aberta ou contato
// já no store), senão as iniciais; "Lead desde … · via …" -----
const contactById = useMapGetter('contacts/getContact');
const selectedChat = useMapGetter('getSelectedChat');
const currentChatSender = computed(() => selectedChat.value?.meta?.sender);
const avatarUrl = computed(
  () =>
    (inConversation.value && currentChatSender.value?.thumbnail) ||
    contactById.value?.(props.lead?.contact_id)?.thumbnail ||
    ''
);
const iniciais = nome => {
  const partes = (nome || '').trim().split(/\s+/).filter(Boolean);
  if (!partes.length) return '';
  const ultima = partes.length > 1 ? partes[partes.length - 1][0] : '';
  return `${partes[0][0]}${ultima}`.toUpperCase();
};
const leadDesde = computed(() => {
  const criado = props.lead?.created_at;
  const partes = [];
  if (criado)
    partes.push(
      t('RAMON.LEAD_PANEL.SINCE', {
        date: new Date(criado).toLocaleDateString('pt-BR'),
      })
    );
  if (props.lead?.source)
    partes.push(t('RAMON.LEAD_PANEL.VIA', { source: props.lead.source }));
  return partes.join(' · ');
});

// ----- cabeçalho: chips -----
const prescription = computed(() => prescriptionInfo(props.lead));
const prescriptionLabel = computed(() => {
  const p = prescription.value;
  if (!p) return null;
  if (p.lostInstallments > 0 && p.monthlyValue)
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
      value: formatBrl(p.monthlyValue),
    });
  if (p.lostInstallments > 0)
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', {
      count: p.lostInstallments,
    });
  if (p.monthsToCliff <= 6)
    return t(
      'RAMON.KANBAN.CARD.PRESCRIPTION_SOON',
      { months: p.monthsToCliff },
      p.monthsToCliff
    );
  return null;
});
const bleeding = computed(() => prescription.value?.lostInstallments > 0);

const formattedValue = computed(() =>
  props.lead?.value == null || props.lead?.value === ''
    ? null
    : formatBrl(props.lead.value)
);

// Badge "estimado": valor_estimado.origem === 'auto' (regra da tese calculou
// sozinha); some assim que o valor é editado à mão.
const valorEstimadoAuto = computed(
  () => props.lead?.custom_attributes?.valor_estimado?.origem === 'auto'
);

// try/catch único dos campos editáveis do Resumo (valor, tese, benefício,
// DCB, canal): no erro só avisa — o lead da store não mudou.
const save = async payload => {
  try {
    await store.dispatch('leads/update', { id: props.lead.id, ...payload });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  }
};

// ----- valor: chip do cabeçalho vira input ao clicar -----
const valueEditing = ref(false);
const valueDraft = ref('');
const valueInput = ref(null);
const editValue = async () => {
  valueDraft.value = formatBrl(props.lead?.value);
  valueEditing.value = true;
  await nextTick();
  valueInput.value?.focus();
  valueInput.value?.select();
};
// Enter/blur salva; Esc fecha antes do blur (que então não salva nada).
const saveValue = () => {
  if (!valueEditing.value) return;
  valueEditing.value = false;
  const next = parseBrlInput(valueDraft.value);
  // texto inválido não-vazio: descarta (evita apagar o valor)
  if (next === null && valueDraft.value.trim() !== '') return;
  const prev = props.lead?.value == null ? null : Number(props.lead.value);
  if (next !== prev) save({ value: next });
};

// ----- etapa editável no chip (mesma guarda do LeadFields: perda pede motivo,
// ganho sem valor pede valor — senão o backend recusa com 422) -----
const stageId = ref(props.lead?.lead_stage_id ?? null);
const lostModalOpen = ref(false);
const wonPrompt = ref(false);
const wonValue = ref('');

watch(
  () => props.lead,
  (l, prev) => {
    if (l?.id !== prev?.id) {
      stageId.value = l?.lead_stage_id ?? null;
      lostModalOpen.value = false;
      wonPrompt.value = false;
      valueEditing.value = false;
      return;
    }
    // broadcast no mesmo lead: não mexer com prompt aberto nem select focado
    const focused = document.activeElement?.dataset?.testid;
    if (!lostModalOpen.value && !wonPrompt.value && focused !== 'panel-stage') {
      stageId.value = l?.lead_stage_id ?? null;
    }
  }
);

// Bolinha da etapa no campo "Etapa do funil": cor da etapa; sem cor
// configurada, cinza neutro.
const corEtapa = computed(
  () =>
    stages.value?.find(s => s.id === stageId.value)?.color ||
    DEFAULT_STAGE_COLOR
);

// ----- Onda B: cartões do resumo -----
const probability = computed(() => {
  const p = stages.value?.find(s => s.id === stageId.value)?.probability;
  return p == null ? null : Number(p);
});
// stage_entered_at porque created_at NÃO está no payload do lead (verificado
// no _lead.json.jbuilder) — e "nesta etapa há Xd" casa com a régua de parado.
const daysInStage = computed(() => {
  if (!props.lead?.stage_entered_at) return null;
  const diff = Date.now() - new Date(props.lead.stage_entered_at).getTime();
  return Number.isNaN(diff) ? null : Math.max(0, Math.floor(diff / 86400000));
});
// partes do apoio: números em mono (Geist Mono), separadas por " · "
const andamentoApoio = computed(() =>
  [
    daysInStage.value != null
      ? {
          texto: t('RAMON.LEAD_PANEL.ANDAMENTO.IN_STAGE', {
            days: daysInStage.value,
          }),
        }
      : null,
    probability.value != null
      ? {
          rotulo: t('RAMON.LEAD_PANEL.ANDAMENTO.CHANCE'),
          texto: `${probability.value}%`,
          mono: true,
        }
      : null,
  ].filter(Boolean)
);
// Última simulação (gravada pelo Simulador em custom_attributes): linha no
// Andamento + form do Simulador pré-preenchido. Sem simulação, nada aparece.
const ultimaSim = computed(
  () => props.lead?.custom_attributes?.ultima_simulacao || null
);
const ultimaSimPartes = computed(() => {
  const s = ultimaSim.value;
  if (!s) return [];
  return [
    s.atrasados != null
      ? {
          rotulo: t('RAMON.LEAD_PANEL.ANDAMENTO.LAST_SIM_ATRASADOS'),
          valor: `~${formatBrl(s.atrasados)}`,
        }
      : null,
    s.mensal != null
      ? {
          rotulo: t('RAMON.LEAD_PANEL.ANDAMENTO.LAST_SIM_RMI'),
          valor: `~${formatBrl(s.mensal)}`,
        }
      : null,
    s.em
      ? {
          rotulo: t('RAMON.LEAD_PANEL.ANDAMENTO.LAST_SIM_EM'),
          valor: new Date(s.em).toLocaleDateString('pt-BR', {
            day: '2-digit',
            month: '2-digit',
          }),
        }
      : null,
  ].filter(Boolean);
});
// ----- Temperatura (heurística local, só na conversa) + Risco de esfriar -----
const currentChat = useMapGetter('getSelectedChat');
const chatMessages = computed(() => currentChat.value?.messages || []);
const { nivel, hesitando } = useTemperatura(chatMessages);
const risco = computed(() => Boolean(props.lead?.stalled));
const followUpPending = ref(false);
const RECUSAS = ['no_conversation', 'open_follow_up', 'recent_follow_up'];
const prepararRetomada = async () => {
  if (followUpPending.value) return;
  followUpPending.value = true;
  try {
    await store.dispatch('leads/followUpDraft', props.lead.id);
    useAlert(t('RAMON.RISCO.PREPARADO'));
  } catch (e) {
    // 422 do backend diz POR QUE não dá pra preparar (antes: "em preparo" mentiroso)
    const recusa = e?.response?.data;
    useAlert(
      RECUSAS.includes(recusa?.reason)
        ? t(
            `RAMON.RISCO.RECUSA.${recusa.reason.toUpperCase()}`,
            { days: recusa.days_ago, gap: recusa.min_gap_days },
            Number(recusa.days_ago) || 0
          )
        : t('RAMON.FUNIL.SAVE_ERROR')
    );
  } finally {
    followUpPending.value = false;
  }
};

const docsPct = computed(() => {
  const total = Number(props.lead?.docs_total) || 0;
  if (!total) return 0;
  return Math.round(((Number(props.lead?.docs_received) || 0) / total) * 100);
});
const contactOpen = ref(false);

const commitStage = async (targetId, extra = {}) => {
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      lead_stage_id: targetId,
      ...extra,
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    stageId.value = props.lead?.lead_stage_id ?? null;
  } finally {
    lostModalOpen.value = false;
    wonPrompt.value = false;
  }
};

const onStageChange = targetId => {
  stageId.value = targetId;
  lostModalOpen.value = false;
  wonPrompt.value = false;
  const target = stages.value.find(s => s.id === targetId);
  if (target?.is_lost && !props.lead?.lost_reason) {
    lostModalOpen.value = true;
    return;
  }
  // Ganho: SEMPRE pede confirmação, pré-preenchida quando o lead já tem valor
  // (o automático da Onda 3 não pode virar "valor de contrato" em silêncio).
  if (target?.is_won) {
    wonValue.value = formatBrl(props.lead?.value);
    wonPrompt.value = true;
    return;
  }
  commitStage(targetId);
};

const confirmLostStage = ({ lostReason }) =>
  commitStage(stageId.value, { lost_reason: lostReason });
const cancelLostStage = () => {
  lostModalOpen.value = false;
  stageId.value = props.lead?.lead_stage_id ?? null;
};
const confirmWonStage = () => {
  const parsed = parseBrlInput(wonValue.value);
  commitStage(stageId.value, parsed == null ? {} : { value: parsed });
};
const skipWonStage = () => commitStage(stageId.value);

// ----- + Tarefa: form inline. Tipo Reunião = mesmo efeito do Cal.com no
// backend (etapa, Closer, rascunho de confirmação, lembretes internos) -----
const TASK_KINDS = [
  { kind: 'follow_up', id: 'task', label: 'KIND_TASK' },
  { kind: 'meeting', id: 'meeting', label: 'KIND_MEETING' },
];
const taskFormOpen = ref(false);
const taskKind = ref('follow_up');
const taskTitle = ref('');
const taskDate = ref('');
const isMeetingForm = computed(() => taskKind.value === 'meeting');
// nota-rascunho de confirmação nasce no backend: recarrega as notas
const notesTick = ref(0);
const tomorrowAt9 = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(9, 0, 0, 0);
  return d;
};
// guard de duplo-clique: dois cliques rápidos criavam a tarefa em dobro
const savingTask = ref(false);
// reunião aberta devolvida pelo 409: pergunta antes de marcar outra
const reuniaoAberta = ref(null);
const reuniaoAbertaQuando = computed(() => {
  if (!reuniaoAberta.value?.due_at) return '';
  return new Date(reuniaoAberta.value.due_at).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
});
const addTask = async (force = false) => {
  if (savingTask.value || (isMeetingForm.value && !taskDate.value)) return;
  reuniaoAberta.value = null;
  savingTask.value = true;
  const title = taskTitle.value.trim();
  const due = taskDate.value ? new Date(taskDate.value) : tomorrowAt9();
  try {
    if (isMeetingForm.value) {
      await store.dispatch('leads/agendarReuniao', {
        id: props.lead.id,
        startsAt: due.toISOString(),
        title,
        force: force === true,
      });
      notesTick.value += 1;
      useAlert(t('RAMON.TASKS.MEETING_SCHEDULED'));
    } else {
      await store.dispatch('leadTasks/create', {
        leadId: props.lead.id,
        title: title || t('RAMON.KANBAN.BELL.DEFAULT_TITLE'),
        kind: 'follow_up',
        dueAt: due.toISOString(),
      });
    }
    taskTitle.value = '';
    taskDate.value = '';
    taskKind.value = 'follow_up';
    taskFormOpen.value = false;
  } catch (e) {
    if (isMeetingForm.value && e?.response?.status === 409) {
      reuniaoAberta.value = e.response.data?.task || {};
      return;
    }
    useAlert(
      t(
        isMeetingForm.value
          ? 'RAMON.TASKS.MEETING_ERROR'
          : 'RAMON.TASKS.CREATE_ERROR'
      )
    );
  } finally {
    savingTask.value = false;
  }
};

// ----- Reunião (Closer): Qualificada / Não qualificada no Andamento quando
// há reunião em jogo — etapa de reunião (pelo label fixo do seed), reunião
// já passada ou resultado já registrado -----
const STAGE_REUNIAO_REALIZADA = 'fase-reuniao-realizada';
const MEETING_STAGE_LABELS = ['fase-reuniao-agendada', STAGE_REUNIAO_REALIZADA];
const tasksByLead = useMapGetter('leadTasks/getByLead');
const leadStage = computed(() =>
  stages.value?.find(s => s.id === props.lead?.lead_stage_id)
);
const showReuniao = computed(() => {
  if (MEETING_STAGE_LABELS.includes(leadStage.value?.label)) return true;
  if (props.lead?.reuniao_resultado) return true;
  return (tasksByLead.value?.(props.lead?.id) || []).some(
    task => task.kind === 'meeting' && new Date(task.due_at) < Date.now()
  );
});

// ----- notas: o painel carrega uma vez e usa no item Notas, no contador e na
// "Última nota" do Resumo. follow_up_last_at muda no broadcast lead.updated
// quando a retomada grava nota + contador (mesma transação); notesTick sobe
// quando a reunião marcada aqui grava o rascunho → as notas recarregam -----
const notes = ref([]);
const loadNotes = async id => {
  try {
    const { data } = await LeadsAPI.getNotes(id);
    notes.value = data.payload || [];
  } catch (e) {
    // painel segue utilizável sem as notas; salvar avisa se falhar
    notes.value = [];
  }
};
watch(
  () => [props.lead?.id, props.lead?.follow_up_last_at, notesTick.value],
  ([id], prev) => {
    if (id !== prev?.[0]) notes.value = [];
    if (id) loadNotes(id);
  },
  { immediate: true }
);
const onNoteCreated = note => {
  notes.value = [...notes.value, note];
};
const ultimaNota = computed(() => notes.value[notes.value.length - 1]);
const ultimaNotaQuando = computed(() =>
  ultimaNota.value?.created_at
    ? dynamicTime(new Date(ultimaNota.value.created_at).getTime() / 1000)
    : ''
);

// ----- navegação por ícone -----
const { activeTab, setTab } = useLeadPanelTabs();
// Conversa do lead na URL da API (display_id): na conversa, a aberta; na
// gaveta, a do lead — o mesmo id que o dock usa (hoje coincidem em produção).
const conversaId = computed(
  () => props.conversationId || props.lead?.conversation_id || null
);
// Docs: checklist da tese e/ou arquivos recebidos na conversa
const temDocs = computed(() =>
  Boolean(props.lead?.thesis_id || conversaId.value)
);
// Contrato só com contrato em jogo: Reunião realizada ou depois na posição do
// funil (perda não conta), ganho, ou ZapSign já gerado.
const showContrato = computed(() => {
  if (props.lead?.custom_attributes?.zapsign) return true;
  const stage = leadStage.value;
  if (!stage || stage.is_lost) return false;
  if (stage.is_won) return true;
  const realizada = stages.value.find(s => s.label === STAGE_REUNIAO_REALIZADA);
  return Boolean(realizada) && stage.position >= realizada.position;
});
// Qualificação no topo do Resumo enquanto o lead está nas 2 primeiras etapas
// abertas do funil (Novo/Qualificação, pela posição); depois desce.
const qualificacaoNoTopo = computed(() => {
  const abertas = (stages.value || [])
    .filter(s => !s.is_won && !s.is_lost)
    .sort((a, b) => a.position - b.position);
  return abertas.slice(0, 2).some(s => s.id === props.lead?.lead_stage_id);
});
const simuladorDot = computed(() =>
  props.lead?.custom_attributes?.ultima_simulacao ? 'bg-n-teal-9' : null
);
// Dot âmbar: existe item de documento ainda não recebido (docs_total/received
// vêm do jbuilder — Task 3; antes dela o dot fica apagado, sem erro).
const docsDot = computed(() =>
  props.lead?.docs_total > 0 &&
  props.lead?.docs_received < props.lead?.docs_total
    ? 'bg-n-amber-9'
    : null
);
const NAV = computed(() => [
  { id: 'resumo', label: 'SUMMARY', icon: 'i-lucide-layout-list' },
  ...(temDocs.value
    ? [
        {
          id: 'documentos',
          label: 'DOCUMENTS',
          icon: 'i-lucide-file-check',
          dot: docsDot,
        },
      ]
    : []),
  { id: 'playbook', label: 'PLAYBOOK', icon: 'i-lucide-message-square-text' },
  {
    id: 'notas',
    label: 'NOTES',
    icon: 'i-lucide-notebook-pen',
    count: notes.value.length,
  },
  {
    id: 'simulador',
    label: 'SIMULADOR',
    icon: 'i-lucide-calculator',
    dot: simuladorDot,
  },
  ...(showContrato.value
    ? [{ id: 'contrato', label: 'CONTRACT', icon: 'i-lucide-file-pen-line' }]
    : []),
  { id: 'atividade', label: 'ACTIVITY', icon: 'i-lucide-activity' },
]);
const shownTab = computed(() => {
  if (activeTab.value === 'documentos' && !temDocs.value) return 'resumo';
  if (activeTab.value === 'contrato' && !showContrato.value) return 'resumo';
  return activeTab.value;
});

// Simular abre largo por cima da conversa (não cabe nos 400px do painel);
// a aba de baixo não muda, então fechar devolve o painel como estava.
const simuladorAberto = ref(false);
const navAtivo = computed(() =>
  simuladorAberto.value ? 'simulador' : shownTab.value
);
const onNav = id => {
  if (id === 'simulador') simuladorAberto.value = true;
  else setTab(id);
};
// No document (antes do window): o Esc fecha só o Simulador, sem chegar à
// gaveta do Kanban, que também fecha no Esc (onKeyStroke no window). Com o
// foco num campo o Esc não fecha: o que foi digitado no form se perderia.
const CAMPOS = ['INPUT', 'SELECT', 'TEXTAREA'];
onKeyStroke(
  'Escape',
  e => {
    if (!simuladorAberto.value) return;
    e.stopPropagation();
    if (CAMPOS.includes(e.target?.tagName)) return;
    simuladorAberto.value = false;
  },
  { target: document }
);
watch(
  () => props.lead?.id,
  () => {
    simuladorAberto.value = false;
  }
);
const dossieRoute = computed(() => ({
  name: 'ramon_lead_dossie',
  params: { leadId: props.lead.id },
}));

// ----- "Dados do contato": LeadFields (o que o Resumo não edita) recolhido -----
const fieldsEl = ref(null);
const onCompleteData = async () => {
  setTab('resumo');
  contactOpen.value = true;
  await nextTick();
  fieldsEl.value?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

// ----- campos derivados -----
// Responsáveis: só o gestor troca SDR/Closer (playbook §13); os outros leem.
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const agentsGetter = useMapGetter('agents/getAgents');
const agents = computed(() => agentsGetter.value || []);
const responsaveis = computed(() => [
  { campo: 'sdr', rotulo: 'RAMON.DRAWER.SDR', nome: props.lead?.sdr_name },
  {
    campo: 'closer',
    rotulo: 'RAMON.DRAWER.CLOSER',
    nome: props.lead?.closer_name,
  },
]);
const activeTheses = computed(() =>
  (theses.value || []).filter(thesis => thesis.active)
);
const thesisFora = computed(
  () =>
    props.lead?.thesis_id &&
    !activeTheses.value.some(th => th.id === props.lead.thesis_id)
);
// select do Caso: '' = limpar (null); ids numéricos viram Number
const saveSelect = (key, raw, numeric = true) => {
  const val = raw === '' ? null : raw;
  save({ [key]: numeric && val != null ? Number(val) : val });
};

const copyPhone = async () => {
  try {
    await copyTextToClipboard(props.lead.contact_phone);
    useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
  }
};

// ----- seções nativas do Chatwoot (agente/time/prioridade/etiquetas/macros)
// recolhidas: não existem no mock 1f e "sujavam" o fim do Resumo -----
const conversationExtrasOpen = ref(false);

// ----- "Não é lead" (destrutivo: confirmação inline, só na conversa) -----
// Excluir lead é só do administrador (regra 06/10; o backend também recusa).
const podeDescartar = computed(() => inConversation.value && isAdmin.value);
const discardPrompt = ref(false);
// "⋯" ao lado do nome: "Não é lead" e, para admin, "Rodar fluxo…"
const menuAberto = ref(false);
// "Rodar fluxo…" (Automações em fluxo, B3): só admin (isAdmin acima) — a API dos fluxos é admin-only
// Só no drawer: na conversa o "Rodar fluxo…" fica no ⋯ do cabeçalho (MoreActions), com {conversation_id}
const rodandoFluxo = ref(null); // alvo congelado no clique (trocar de lead por trás do modal não muda o destino)
const podeRodarFluxo = computed(() => !inConversation.value && isAdmin.value);
const abrirRodarFluxo = () => {
  menuAberto.value = false;
  rodandoFluxo.value = { lead_id: props.lead.id };
};
const menuEl = ref(null);
onClickOutside(menuEl, () => {
  menuAberto.value = false;
});
const pedirDescarte = () => {
  menuAberto.value = false;
  discardPrompt.value = true;
};
const discarding = ref(false);
const discard = async () => {
  if (!props.lead || discarding.value) return;
  discarding.value = true;
  try {
    await store.dispatch('leads/delete', props.lead.id);
    emit('discarded');
  } catch (e) {
    useAlert(t('RAMON.LEAD_PANEL.DISCARD_ERROR'));
  } finally {
    discarding.value = false;
    discardPrompt.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full min-w-0 overflow-hidden">
    <!-- navegação só por ícone, no topo do painel (nome no title) -->
    <nav
      class="flex shrink-0 gap-1 px-3 py-2 border-b border-n-weak"
      :aria-label="$t('RAMON.LEAD_PANEL.NAV_LABEL')"
    >
      <button
        v-for="item in NAV"
        :key="item.id"
        type="button"
        :aria-label="$t(`RAMON.LEAD_PANEL.TABS.${item.label}`)"
        :title="$t(`RAMON.LEAD_PANEL.TABS.${item.label}`)"
        :aria-current="navAtivo === item.id ? 'page' : undefined"
        :data-testid="`lead-nav-${item.id}`"
        :class="[
          NAV_ICONE,
          navAtivo === item.id ? NAV_ICONE_ATIVO : NAV_ICONE_INATIVO,
        ]"
        @click="onNav(item.id)"
      >
        <span class="relative">
          <span class="block size-5" :class="item.icon" />
          <span
            v-if="item.dot?.value"
            :data-testid="`lead-nav-dot-${item.id}`"
            class="absolute -top-0.5 -right-1 size-2 rounded-full"
            :class="item.dot.value"
          />
          <span
            v-if="item.count"
            :data-testid="`lead-nav-count-${item.id}`"
            class="absolute -top-1.5 left-3 min-w-4 rounded-full px-1 font-mono text-[9.5px] font-medium leading-4 text-center"
            :class="TOM.slate"
          >
            {{ item.count }}
          </span>
        </span>
      </button>
    </nav>

    <!-- corpo da aba ativa -->
    <div
      data-testid="lead-panel-corpo"
      class="flex flex-col flex-1 gap-3 min-w-0 overflow-y-auto overflow-x-hidden p-3"
    >
      <template v-if="shownTab === 'resumo'">
        <!-- identidade: foto, nome (+ ficha e ⋯), telefone, desde quando -->
        <div
          data-testid="panel-identidade"
          class="flex flex-col items-center gap-1 pt-1 text-center min-w-0"
        >
          <img
            v-if="avatarUrl"
            data-testid="panel-avatar"
            :src="avatarUrl"
            alt=""
            class="size-[72px] rounded-full object-cover"
          />
          <span
            v-else
            data-testid="panel-avatar-iniciais"
            class="flex items-center justify-center size-[72px] rounded-full text-2xl font-semibold"
            :class="TOM.blue"
          >
            {{ iniciais(lead.name) }}
          </span>
          <div class="flex items-center justify-center gap-0.5 max-w-full mt-2">
            <h2 class="min-w-0 truncate text-xl font-semibold text-n-slate-12">
              {{ lead.name }}
            </h2>
            <router-link
              v-if="lead?.id"
              v-slot="{ navigate }"
              custom
              :to="dossieRoute"
            >
              <Button
                data-testid="lead-abrir-ficha"
                xs
                ghost
                slate
                icon="i-lucide-external-link"
                class="shrink-0"
                :title="$t('RAMON.FICHA.OPEN_FULL')"
                :aria-label="$t('RAMON.FICHA.OPEN_FULL')"
                @click="
                  navigate($event);
                  emit('navigate');
                "
              />
            </router-link>
            <div
              v-if="podeDescartar || podeRodarFluxo"
              ref="menuEl"
              class="relative shrink-0"
            >
              <Button
                data-testid="lead-more"
                xs
                ghost
                slate
                icon="i-lucide-ellipsis"
                :aria-label="$t('RAMON.LEAD_PANEL.MORE_ACTIONS')"
                :aria-expanded="menuAberto"
                @click="menuAberto = !menuAberto"
              />
              <div
                v-if="menuAberto"
                class="absolute right-0 top-full z-20 mt-1 w-44 text-left"
                :class="MENU"
              >
                <button
                  v-if="podeDescartar"
                  type="button"
                  data-testid="lead-discard"
                  class="flex items-center gap-2 text-n-ruby-11"
                  :class="LINHA"
                  @click="pedirDescarte"
                >
                  <span class="i-lucide-user-x size-4 shrink-0" />
                  {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
                </button>
                <button
                  v-if="podeRodarFluxo"
                  type="button"
                  data-testid="lead-rodar-fluxo"
                  class="flex items-center gap-2"
                  :class="LINHA"
                  @click="abrirRodarFluxo"
                >
                  <span class="i-lucide-workflow size-4 shrink-0" />
                  {{ $t('CAPTAIN_RAMON.FLUXOS.RODAR.ITEM') }}
                </button>
              </div>
            </div>
          </div>
          <Button
            v-if="lead.contact_phone"
            data-testid="panel-phone"
            link
            slate
            class="!text-[15px] tabular-nums"
            :title="$t('RAMON.KANBAN.CARD.COPY_PHONE')"
            :label="formatPhoneBr(lead.contact_phone)"
            @click="copyPhone"
          />
          <p
            v-if="leadDesde"
            data-testid="panel-lead-desde"
            class="text-xs italic text-n-slate-10"
          >
            {{ leadDesde }}
          </p>
          <span
            v-if="prescriptionLabel"
            data-testid="panel-prescription-chip"
            class="mt-1"
            :class="[CHIP, bleeding ? TOM.ruby : TOM.amber]"
          >
            <span class="i-lucide-hourglass size-3 shrink-0" />
            {{ prescriptionLabel }}
          </span>
        </div>

        <RodarFluxo
          v-if="rodandoFluxo"
          :alvo="rodandoFluxo"
          @fechar="rodandoFluxo = null"
        />

        <!-- reunião nova com outra aberta: confirma antes de marcar -->
        <Teleport to="body">
          <ConfirmModal
            v-if="reuniaoAberta"
            :title="$t('RAMON.TASKS.MEETING_CONFLICT_TITLE')"
            :message="
              $t('RAMON.TASKS.MEETING_CONFLICT', {
                quando: reuniaoAbertaQuando,
              })
            "
            :confirm-label="$t('RAMON.TASKS.MEETING_CONFLICT_CONFIRM')"
            confirm-color="blue"
            @confirm="addTask(true)"
            @cancel="reuniaoAberta = null"
          />
        </Teleport>

        <!-- tirar do funil é destrutivo: janela de confirmação do kit -->
        <Teleport to="body">
          <ConfirmModal
            v-if="discardPrompt"
            :title="$t('RAMON.LEAD_PANEL.DISCARD_TITLE')"
            :message="$t('RAMON.LEAD_PANEL.DISCARD_CONFIRM')"
            :confirm-label="$t('RAMON.LEAD_PANEL.DISCARD_ACTION')"
            @confirm="discard"
            @cancel="discardPrompt = false"
          />
        </Teleport>

        <!-- Ações fixas. WhatsApp abre a conversa (gaveta) ou o wa.me (sem
             conversa); no painel da conversa ela já está aberta — botão sai.
             Resolver NÃO entra aqui: já existe no cabeçalho da conversa, e um
             2º ResolveAction registrava o atalho Alt+E em dobro. -->
        <div class="flex gap-1.5">
          <Button
            v-if="lead.conversation_id && !inConversation"
            data-testid="panel-whatsapp"
            sm
            icon="i-lucide-message-square"
            :label="$t('RAMON.KANBAN.CARD.WHATSAPP')"
            class="flex-1"
            @click="emit('openConversation', lead.conversation_id)"
          />
          <a
            v-else-if="!lead.conversation_id && lead.contact_phone"
            data-testid="panel-whatsapp-wa-me"
            :href="waMeUrl(lead.contact_phone)"
            target="_blank"
            rel="noopener noreferrer"
            class="flex flex-1 min-w-0"
          >
            <Button
              sm
              tabindex="-1"
              icon="i-lucide-message-square"
              :label="$t('RAMON.KANBAN.CARD.WHATSAPP')"
              class="w-full"
            />
          </a>
          <!-- Sugerir resposta (copiloto) divide a linha com o + Tarefa -->
          <LeadSugerirResposta
            v-if="inConversation && conversationId"
            :conversation-id="conversationId"
            class="flex-1"
          />
          <Button
            data-testid="panel-add-task"
            sm
            faded
            slate
            :label="$t('RAMON.TASKS.ADD')"
            class="flex-1"
            @click="taskFormOpen = !taskFormOpen"
          />
        </div>

        <div
          v-if="taskFormOpen"
          data-testid="panel-task-form"
          class="flex flex-col gap-2 mt-2"
          :class="CARTAO"
        >
          <div class="flex gap-1.5">
            <Button
              v-for="k in TASK_KINDS"
              :key="k.kind"
              :data-testid="`panel-task-kind-${k.id}`"
              xs
              :variant="taskKind === k.kind ? 'solid' : 'faded'"
              :color="taskKind === k.kind ? 'blue' : 'slate'"
              :label="$t(`RAMON.TASKS.${k.label}`)"
              @click="taskKind = k.kind"
            />
          </div>
          <input
            v-model="taskTitle"
            data-testid="panel-task-title"
            :placeholder="
              $t(
                isMeetingForm
                  ? 'RAMON.TASKS.MEETING_TITLE_PLACEHOLDER'
                  : 'RAMON.TASKS.ADD_TITLE_PLACEHOLDER'
              )
            "
            :class="CAMPO"
          />
          <input
            v-model="taskDate"
            data-testid="panel-task-date"
            type="datetime-local"
            :title="
              $t(
                isMeetingForm
                  ? 'RAMON.TASKS.MEETING_DATE_HINT'
                  : 'RAMON.TASKS.DATE_HINT'
              )
            "
            class="font-mono"
            :class="CAMPO"
          />
          <p v-if="isMeetingForm" class="text-xs text-n-slate-10">
            {{ $t('RAMON.TASKS.MEETING_HINT') }}
          </p>
          <div class="flex justify-end gap-2">
            <Button
              data-testid="panel-task-cancel"
              sm
              faded
              slate
              :label="$t('RAMON.FUNIL.CANCEL')"
              @click="taskFormOpen = false"
            />
            <Button
              data-testid="panel-task-save"
              sm
              :label="$t('RAMON.FUNIL.SAVE')"
              :disabled="savingTask || (isMeetingForm && !taskDate)"
              @click="addTask()"
            />
          </div>
        </div>

        <!-- campos rotulados (como na referência): rótulo em cima, controle
             largo embaixo; editar = mexer no próprio controle -->
        <div data-testid="panel-campos" class="flex flex-col gap-4">
          <div>
            <p class="mb-1.5" :class="TITULO">
              {{ $t('RAMON.LEAD_PANEL.FIELDS.STAGE') }}
            </p>
            <div class="relative">
              <span
                class="absolute left-3 top-1/2 -translate-y-1/2 size-2.5 rounded-full pointer-events-none"
                :style="{ backgroundColor: corEtapa }"
              />
              <select
                data-testid="panel-stage"
                :value="stageId"
                :aria-label="$t('RAMON.LEAD_PANEL.FIELDS.STAGE')"
                class="!pl-8 font-medium"
                :class="SELECT_GRANDE"
                @change="e => onStageChange(Number(e.target.value))"
              >
                <option v-for="s in stages" :key="s.id" :value="s.id">
                  {{ s.name }}
                </option>
              </select>
            </div>
            <LostReasonModal
              v-if="lostModalOpen"
              :lost-reasons="lostReasons"
              @confirm-move="confirmLostStage"
              @cancel-move="cancelLostStage"
            />
            <div
              v-if="wonPrompt"
              data-testid="stage-won-prompt"
              class="flex flex-col gap-2 mt-2"
              :class="CARTAO"
            >
              <label class="text-xs text-n-slate-10">{{
                $t('RAMON.FUNIL.WON.VALUE_LABEL')
              }}</label>
              <input
                v-model="wonValue"
                data-testid="stage-won-value"
                type="text"
                inputmode="decimal"
                class="font-mono"
                :class="CAMPO"
                @keyup.enter="confirmWonStage"
              />
              <div class="flex justify-end gap-2">
                <Button
                  data-testid="stage-won-skip"
                  sm
                  faded
                  slate
                  :label="$t('RAMON.FUNIL.WON.SKIP')"
                  @click="skipWonStage"
                />
                <Button
                  data-testid="stage-won-save"
                  sm
                  :label="$t('RAMON.FUNIL.WON.SAVE')"
                  @click="confirmWonStage"
                />
              </div>
            </div>
          </div>

          <!-- valor: clicar edita no lugar (Enter/fora salva, Esc desiste) -->
          <div>
            <p class="mb-1.5" :class="TITULO">
              {{ $t('RAMON.DRAWER.VALUE') }}
            </p>
            <input
              v-if="valueEditing"
              ref="valueInput"
              v-model="valueDraft"
              data-testid="field-value"
              type="text"
              inputmode="decimal"
              :aria-label="$t('RAMON.DRAWER.VALUE')"
              class="font-mono"
              :class="CAMPO_GRANDE"
              @blur="saveValue"
              @keyup.enter="saveValue"
              @keyup.esc="valueEditing = false"
            />
            <button
              v-else
              type="button"
              data-testid="panel-value-chip"
              :title="$t('RAMON.LEAD_PANEL.VALUE_EDIT')"
              class="flex items-center gap-2 text-left"
              :class="CAMPO_GRANDE"
              @click="editValue"
            >
              <span
                :class="
                  formattedValue ? 'font-mono font-medium' : 'text-n-slate-10'
                "
              >
                {{ formattedValue || $t('RAMON.LEAD_PANEL.VALUE_ADD') }}
              </span>
              <span
                v-if="valorEstimadoAuto"
                data-testid="value-auto-badge"
                :title="$t('RAMON.DRAWER.VALUE_AUTO_TIP')"
                class="inline-flex items-center gap-0.5 rounded px-1 text-[10px]"
                :class="TOM.blue"
              >
                <span class="i-lucide-sparkles size-2.5" />{{
                  $t('RAMON.DRAWER.VALUE_AUTO')
                }}
              </span>
            </button>
          </div>

          <!-- caso: tese · benefício; DCB · canal -->
          <div data-testid="panel-caso">
            <p class="mb-1.5" :class="TITULO">
              {{ $t('RAMON.LEAD_PANEL.FIELDS.CASE') }}
            </p>
            <div class="grid grid-cols-[3fr_2fr] gap-2">
              <select
                data-testid="field-thesis"
                :value="lead.thesis_id ?? ''"
                :aria-label="$t('RAMON.DRAWER.THESIS')"
                :class="SELECT_GRANDE"
                @change="e => saveSelect('thesis_id', e.target.value)"
              >
                <option value="">{{ $t('RAMON.DRAWER.THESIS') }}</option>
                <!-- tese inativa (ou lista ainda não carregada): mostra a do lead -->
                <option v-if="thesisFora" :value="lead.thesis_id">
                  {{ lead.thesis_name }}
                </option>
                <option v-for="th in activeTheses" :key="th.id" :value="th.id">
                  {{ th.name }}
                </option>
              </select>
              <select
                data-testid="field-benefit"
                :value="lead.benefit_type_id ?? ''"
                :aria-label="$t('RAMON.DRAWER.BENEFIT')"
                :class="SELECT_GRANDE"
                @change="e => saveSelect('benefit_type_id', e.target.value)"
              >
                <option value="">{{ $t('RAMON.DRAWER.BENEFIT') }}</option>
                <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
                  {{ b.name }}
                </option>
              </select>
            </div>
            <div class="grid grid-cols-[3fr_2fr] gap-2 mt-2">
              <label class="relative block">
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-n-slate-10 pointer-events-none"
                >
                  {{ $t('RAMON.LEAD_PANEL.FIELDS.DCB') }}
                </span>
                <input
                  data-testid="field-dcb-em"
                  type="date"
                  :value="lead.dcb_em || ''"
                  class="!pl-11 font-mono"
                  :class="[CAMPO_GRANDE, bleeding ? '!text-n-ruby-11' : '']"
                  @change="e => save({ dcb_em: e.target.value || null })"
                />
              </label>
              <select
                data-testid="field-channel"
                :value="lead.channel ?? ''"
                :aria-label="$t('RAMON.LEAD_PANEL.FIELDS.CHANNEL')"
                :class="SELECT_GRANDE"
                @change="e => saveSelect('channel', e.target.value, false)"
              >
                <option value="">
                  {{ $t('RAMON.LEAD_PANEL.FIELDS.CHANNEL') }}
                </option>
                <option v-for="c in channels" :key="c.key" :value="c.key">
                  {{ c.label }}
                </option>
              </select>
            </div>
            <p
              v-if="!lead.thesis_id"
              data-testid="no-thesis-hint"
              class="mt-1 text-xs text-n-slate-9"
            >
              {{ $t('RAMON.DRAWER.NO_THESIS_HINT') }}
            </p>
          </div>

          <!-- responsáveis: só o gestor troca (playbook §13); os outros leem -->
          <div data-testid="panel-responsaveis">
            <p class="mb-1.5" :class="TITULO">
              {{ $t('RAMON.LEAD_PANEL.FIELDS.OWNERS') }}
            </p>
            <div class="flex flex-col gap-2">
              <div
                v-for="r in responsaveis"
                :key="r.campo"
                class="flex items-center gap-2"
              >
                <span class="w-12 shrink-0 text-xs text-n-slate-10">
                  {{ $t(r.rotulo) }}
                </span>
                <div class="relative flex-1 min-w-0">
                  <span
                    class="absolute left-2 top-1/2 -translate-y-1/2 flex items-center justify-center size-6 rounded-full text-[10px] font-semibold pointer-events-none"
                    :class="r.nome ? TOM.blue : TOM.slate"
                  >
                    {{ iniciais(r.nome) || '?' }}
                  </span>
                  <select
                    v-if="isAdmin"
                    :data-testid="`field-${r.campo}`"
                    :value="lead[`${r.campo}_id`] ?? ''"
                    :aria-label="$t(r.rotulo)"
                    class="!pl-10"
                    :class="SELECT_GRANDE"
                    @change="e => saveSelect(`${r.campo}_id`, e.target.value)"
                  >
                    <option value="">—</option>
                    <option v-for="a in agents" :key="a.id" :value="a.id">
                      {{ a.name }}
                    </option>
                  </select>
                  <p
                    v-else
                    :data-testid="`panel-${r.campo}`"
                    class="flex items-center !pl-10 truncate"
                    :class="CAMPO_GRANDE"
                  >
                    {{ r.nome || '—' }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- próximo passo (tarefa aberta mais próxima) -->
          <LeadNextAction :lead-id="lead.id" @notes-changed="notesTick += 1" />
        </div>

        <QualificacaoViva
          v-if="qualificacaoNoTopo"
          :lead="lead"
          :context="context"
        />

        <LeadCopilot
          v-if="inConversation && conversationId"
          :conversation-id="conversationId"
        />

        <!-- Andamento -->
        <div :class="CARTAO" data-testid="panel-card-andamento">
          <p :class="TITULO">
            {{ $t('RAMON.LEAD_PANEL.ANDAMENTO.TITLE') }}
          </p>
          <!-- etapa: o controle é a pílula do cabeçalho; aqui só a esteira -->
          <MiniEsteira class="mt-2" :stages="stages" :current-id="stageId" />
          <p
            v-if="andamentoApoio.length"
            class="mt-1.5 text-xs text-n-slate-11"
          >
            <template v-for="(parte, i) in andamentoApoio" :key="i">
              <span v-if="i"> · </span>
              <span v-if="parte.rotulo">{{ `${parte.rotulo} ` }}</span>
              <span :class="{ 'font-mono': parte.mono }">{{
                parte.texto
              }}</span>
            </template>
          </p>
          <button
            v-if="ultimaSimPartes.length"
            type="button"
            data-testid="panel-ultima-simulacao"
            class="block w-full p-0 mt-1.5 text-left text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="simuladorAberto = true"
          >
            {{ $t('RAMON.LEAD_PANEL.ANDAMENTO.LAST_SIM') }}
            <template v-for="(parte, i) in ultimaSimPartes" :key="i">
              <span v-if="i"> · </span>
              <span class="whitespace-nowrap">
                {{ parte.rotulo }}
                <span class="font-mono">{{ parte.valor }}</span>
              </span>
            </template>
          </button>
          <LeadReuniao v-if="showReuniao" :lead="lead" />
        </div>

        <!-- Temperatura (só na conversa; heurística local) -->
        <div
          v-if="inConversation && nivel"
          :class="CARTAO"
          data-testid="panel-card-termometro"
        >
          <p :class="TITULO">
            {{ $t('RAMON.TERMOMETRO.TITLE') }}
          </p>
          <div class="mt-2 flex items-center gap-2">
            <div
              class="relative h-1.5 flex-1 rounded-full bg-gradient-to-r from-n-ruby-9 via-n-amber-9 to-n-teal-9 opacity-80"
            >
              <span
                class="absolute -top-1 h-3.5 w-1 rounded bg-n-slate-12"
                :style="{
                  left:
                    nivel === 'quente'
                      ? '85%'
                      : nivel === 'morna'
                        ? '48%'
                        : '10%',
                }"
              />
            </div>
            <span
              class="text-[11px] font-bold uppercase"
              :class="
                nivel === 'quente'
                  ? 'text-n-teal-11'
                  : nivel === 'morna'
                    ? 'text-n-amber-11'
                    : 'text-n-ruby-11'
              "
            >
              {{ $t(`RAMON.TERMOMETRO.${nivel.toUpperCase()}`) }}
            </span>
          </div>
          <p v-if="hesitando" class="mt-1.5 text-xs text-n-slate-11">
            {{ $t('RAMON.TERMOMETRO.HESITANDO') }}
          </p>
        </div>

        <!-- Risco de esfriar (stalled) -->
        <div
          v-if="risco"
          :class="[CARTAO_STATUS, FILETE.ruby]"
          data-testid="panel-card-risco"
        >
          <p class="text-[12.5px] font-bold text-n-ruby-11">
            {{ $t('RAMON.RISCO.TITLE') }}
          </p>
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{
              $t('RAMON.RISCO.APOIO', {
                days: daysInStage ?? 0,
                count: Number(lead.follow_up_count) || 0,
              })
            }}
          </p>
          <Button
            v-if="lead.conversation_id"
            data-testid="risco-preparar-retomada"
            link
            xs
            class="mt-2"
            :label="$t('RAMON.RISCO.PREPARAR')"
            :disabled="followUpPending"
            @click="prepararRetomada"
          />
          <p
            v-else
            data-testid="risco-sem-conversa"
            class="mt-2 text-xs text-n-slate-10"
          >
            {{ $t('RAMON.RISCO.RECUSA.NO_CONVERSATION') }}
          </p>
        </div>

        <!-- Documentos (cartão inteiro clicável → aba Documentos) -->
        <button
          v-if="lead.thesis_id && lead.docs_total"
          type="button"
          :class="CARTAO"
          class="text-left w-full border-solid hover:border-n-blue-9/40"
          data-testid="panel-card-docs"
          @click="setTab('documentos')"
        >
          <div class="flex items-center justify-between">
            <p :class="TITULO">
              {{ $t('RAMON.DOCS.TITLE') }}
            </p>
            <span class="font-mono text-xs font-semibold text-n-slate-12">
              {{
                $t('RAMON.DOCS.COUNT', {
                  received: lead.docs_received || 0,
                  total: lead.docs_total,
                })
              }}
            </span>
          </div>
          <div class="mt-2 h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div class="h-full bg-n-blue-9" :style="{ width: `${docsPct}%` }" />
          </div>
        </button>

        <QualificacaoViva
          v-if="!qualificacaoNoTopo"
          :lead="lead"
          :context="context"
        />

        <LeadQuizResumo :lead="lead" />

        <!-- só a última nota, numa linha; a lista inteira mora no item Notas -->
        <button
          v-if="ultimaNota"
          type="button"
          data-testid="panel-ultima-nota"
          class="flex items-center w-full gap-1 p-0 text-left text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="setTab('notas')"
        >
          <span class="shrink-0 text-n-slate-10">
            {{ $t('RAMON.LEAD_PANEL.NOTES.LAST') }}
          </span>
          <span class="truncate">{{ ultimaNota.body }}</span>
          <span class="shrink-0 text-n-slate-10">
            {{ `· ${ultimaNotaQuando}` }}
          </span>
        </button>

        <!-- Dados do contato (recolhido — mesmo padrão do "Mais da conversa") -->
        <div class="min-w-0" :class="SECAO">
          <button
            type="button"
            data-testid="contact-data-toggle"
            class="flex items-center w-full gap-1.5 hover:text-n-slate-12"
            :class="TITULO"
            @click="contactOpen = !contactOpen"
          >
            {{ $t('RAMON.LEAD_PANEL.CONTACT_DATA') }}
            <span
              class="size-3.5 shrink-0"
              :class="
                contactOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
            />
          </button>
          <div
            v-if="contactOpen"
            ref="fieldsEl"
            data-testid="lead-all-fields"
            class="mt-3 min-w-0"
          >
            <LeadFields :lead="lead" />
          </div>
        </div>

        <div
          v-if="inConversation && conversationId"
          class="min-w-0"
          :class="SECAO"
        >
          <button
            type="button"
            data-testid="conversation-extras-toggle"
            class="flex items-center w-full gap-1.5 hover:text-n-slate-12"
            :class="TITULO"
            @click="conversationExtrasOpen = !conversationExtrasOpen"
          >
            {{ $t('RAMON.LEAD_PANEL.CONVERSATION_EXTRAS') }}
            <span
              class="size-3.5 shrink-0"
              :class="
                conversationExtrasOpen
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </button>
          <div
            v-if="conversationExtrasOpen"
            class="flex flex-col gap-2 mt-3 min-w-0"
          >
            <ConversationAction :conversation-id="conversationId" />
            <div :class="SECAO">
              <p class="mb-2" :class="TITULO">
                {{ $t('RAMON.LEAD_PANEL.MACROS_TITLE') }}
              </p>
              <MacrosList :conversation-id="conversationId" />
            </div>
          </div>
        </div>
      </template>

      <LeadPlaybook v-else-if="shownTab === 'playbook'" :lead="lead" />

      <LeadNotes
        v-else-if="shownTab === 'notas'"
        :lead-id="lead.id"
        :notes="notes"
        :in-conversation="inConversation"
        @created="onNoteCreated"
      />

      <div v-else-if="shownTab === 'documentos'" class="flex flex-col gap-5">
        <DocChecklist v-if="lead.thesis_id" :lead="lead" :context="context" />
        <ArquivosRecebidos v-if="conversaId" :conversation-id="conversaId" />
      </div>

      <div v-else-if="shownTab === 'atividade'" class="flex flex-col gap-3">
        <LeadHistory :lead-id="lead.id" />
        <!-- linha do tempo completa mora na ficha (Dossiê) -->
        <router-link v-slot="{ navigate }" custom :to="dossieRoute">
          <Button
            data-testid="lead-historico-ficha"
            link
            slate
            xs
            trailing-icon
            icon="i-lucide-arrow-right"
            class="self-start"
            :label="$t('RAMON.LEAD_PANEL.HISTORY_IN_FICHA')"
            @click="
              navigate($event);
              emit('navigate');
            "
          />
        </router-link>
      </div>

      <LeadZapsignCard
        v-else-if="shownTab === 'contrato'"
        :lead="lead"
        @complete-data="onCompleteData"
      />
    </div>

    <!-- Simular largo, ancorado à direita, por cima da conversa -->
    <Teleport to="body">
      <div
        v-if="simuladorAberto"
        data-testid="lead-simulador-largo"
        role="dialog"
        :aria-label="$t('RAMON.LEAD_PANEL.TABS.SIMULADOR')"
        class="fixed inset-y-0 right-0 z-50 flex flex-col w-[min(760px,92vw)] bg-n-solid-2 border-l border-n-weak shadow-xl"
      >
        <div
          class="flex items-center gap-2 shrink-0 px-3 py-2 border-b border-n-weak"
        >
          <Button
            data-testid="lead-simulador-voltar"
            sm
            ghost
            slate
            icon="i-lucide-arrow-left"
            :label="$t('RAMON.LEAD_PANEL.SIMULADOR_BACK')"
            @click="simuladorAberto = false"
          />
          <span class="truncate text-sm font-semibold text-n-slate-12">
            {{ lead.name }}
          </span>
        </div>
        <div class="flex-1 min-h-0 overflow-y-auto p-4">
          <LeadSimulador :lead="lead" :ultima-simulacao="ultimaSim" />
        </div>
      </div>
    </Teleport>
  </div>
</template>
