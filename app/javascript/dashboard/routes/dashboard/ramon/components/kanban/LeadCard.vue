<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { formatBrl, brlCompact } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import { contratoLimpoStatus } from '../../helpers/contratoLimpo';
import { TARDE, desde, diaCurto, horaDe } from '../hoje/hoje';
import Selo from '../hoje/Selo.vue';
import SeloPrazo from '../hoje/SeloPrazo.vue';
import TaskBellMenu from './TaskBellMenu.vue';

// Card enxuto do funil (mockup v2 .card). Próxima ação, triagem e retomadas
// saíram do card — continuam na gaveta do lead (LeadPanelBody).
const props = defineProps({
  lead: { type: Object, required: true },
  focused: { type: Boolean, default: false },
  selectable: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
});
const emit = defineEmits([
  'openConversation',
  'openLead',
  'openDossie',
  'toggleSelect',
]);

const cardEl = ref(null);
watch(
  () => props.focused,
  isFocused => {
    if (isFocused)
      cardEl.value?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
);

const { t } = useI18n();
// useStore não lança fora de um app com store (retorna undefined); leituras de
// getters/dispatch ficam defensivas para o card renderizar em testes sem store.
const store = useStore();

const compactValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return brlCompact(v);
});

const prescription = computed(() => prescriptionInfo(props.lead));
const contrato = computed(() => contratoLimpoStatus(props.lead));
// Prescrição no card só quando crítica: já perde parcelas (ruim) ou ≤ 6 meses.
const prescriptionSelo = computed(() => {
  const p = prescription.value;
  if (!p) return null;
  if (p.lostInstallments > 0 && p.monthlyValue)
    return {
      tom: 'bad',
      label: t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
        value: formatBrl(p.monthlyValue),
      }),
    };
  if (p.lostInstallments > 0)
    return {
      tom: 'bad',
      label: t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', {
        count: p.lostInstallments,
      }),
    };
  if (p.monthsToCliff <= 6)
    return {
      tom: 'warn',
      label: t('RAMON.KANBAN.CARD.PRESCRIPTION_SOON', {
        months: p.monthsToCliff,
      }),
    };
  return null;
});

const ownerName = computed(
  () => props.lead.closer_name || props.lead.sdr_name || null
);
const ownerInitials = computed(() => {
  if (!ownerName.value) return null;
  return ownerName.value
    .trim()
    .split(/\s+/)
    .map(word => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
});

const stage = computed(() => {
  const stages = store?.getters?.['leadConfig/getStages'] || [];
  return stages.find(s => s.id === props.lead.lead_stage_id) || null;
});
const isWon = computed(() => stage.value?.is_won ?? !!props.lead.won_at);
const tese = computed(
  () => props.lead.thesis_name || props.lead.benefit_type_name || null
);
// Sem checklist de documentos, a linha 3 mostra a origem (mockup: "Meta Ads").
const channelLabel = computed(() => {
  const channels = store?.getters?.['leadConfig/getChannels'] || [];
  return channels.find(c => c.key === props.lead.channel)?.label || null;
});
const docsPendentes = computed(
  () =>
    props.lead.docs_total > 0 &&
    props.lead.docs_received < props.lead.docs_total
);

const daysInStage = computed(() => {
  const entered = props.lead.stage_entered_at;
  if (!entered) return null;
  const diff = Date.now() - new Date(entered).getTime();
  if (Number.isNaN(diff)) return null;
  return Math.max(0, Math.floor(diff / 86400000));
});

// Relógio de 30s para o estouro do prazo e o "parado há" andarem sem re-fetch.
const now = ref(Date.now());
let timer = null;
onMounted(() => {
  timer = setInterval(() => {
    now.value = Date.now();
  }, 30000);
});
onUnmounted(() => clearInterval(timer));

// Prazo de 1ª resposta correndo (sem resposta ainda) → SeloPrazo da Onda 3.
const slaDue = computed(() => {
  const sla = props.lead.sla;
  return sla?.due_at && !sla.replied_at ? sla.due_at : null;
});
const slaOverdue = computed(
  () => !!slaDue.value && new Date(slaDue.value).getTime() < now.value
);

// Tempo "quieto" à direita do nome: reunião marcada ("qui 10:00") ou há
// quanto tempo está na etapa ("5h", "8 dias").
const quiet = computed(() => {
  const due = props.lead.next_task_due_at;
  if (
    props.lead.next_task_kind === 'meeting' &&
    due &&
    new Date(due).getTime() >= now.value
  )
    return `${diaCurto(due)} ${horaDe(due)}`;
  if (!props.lead.stage_entered_at) return null;
  const { key, count } = desde(props.lead.stage_entered_at, now.value);
  return t(`RAMON.HOJE.${key}`, { count }, count);
});

// Risco = filete interno de 3px à esquerda: ruby (prescrevendo / apodrecendo
// forte / prazo estourado) tem prioridade sobre âmbar (parado).
const riskClass = computed(() => {
  const limit = stage.value?.stalled_after_days;
  const rotten =
    limit != null && daysInStage.value != null && daysInStage.value > 2 * limit;
  if (prescription.value?.lostInstallments > 0 || rotten || slaOverdue.value)
    return TARDE;
  if (props.lead.stalled) return 'shadow-[inset_3px_0_0_rgb(var(--amber-9))]';
  return '';
});

const onSchedule = async ({ dueAt, title }) => {
  try {
    await store.dispatch('leadTasks/create', {
      leadId: props.lead.id,
      title,
      kind: 'follow_up',
      dueAt,
    });
    useAlert(t('RAMON.KANBAN.CARD.TASK_SCHEDULED'));
  } catch (e) {
    useAlert(t('RAMON.TASKS.CREATE_ERROR'));
  }
};

const ACAO = 'hover:text-n-blue-11';
</script>

<template>
  <div
    ref="cardEl"
    class="group p-3 rounded-[10px] bg-n-background border border-n-weak cursor-pointer transition-colors hover:border-n-strong"
    :class="[riskClass, { 'ring-2 ring-n-blue-9': focused }]"
    @click="emit('openLead', lead)"
  >
    <div class="flex items-center gap-2">
      <button
        v-if="selectable"
        data-testid="select-toggle"
        class="flex items-center justify-center size-3.5 rounded shrink-0 border-[1.5px]"
        :class="selected ? 'bg-n-blue-9 border-n-blue-9' : 'border-n-slate-8'"
        @click.stop="emit('toggleSelect', lead)"
      >
        <span v-if="selected" class="i-lucide-check size-2.5 text-white" />
      </button>
      <button
        data-testid="lead-card-body"
        class="flex-1 min-w-0 text-left"
        @click.stop="emit('openLead', lead)"
      >
        <span class="block truncate text-[13.5px] font-medium text-n-slate-12">
          {{ lead.name }}
        </span>
      </button>
      <SeloPrazo v-if="slaDue" data-testid="sla-pill" :prazo-em="slaDue" />
      <span
        v-else-if="quiet"
        data-testid="lead-quiet"
        class="font-mono text-[11.5px] whitespace-nowrap text-n-slate-9"
      >
        {{ quiet }}
      </span>
    </div>
    <p v-if="tese" class="truncate text-[12.5px] text-n-slate-11">
      {{ tese }}
    </p>

    <div class="flex items-center gap-2.5 mt-2.5 text-xs text-n-slate-9">
      <Selo
        v-if="lead.docs_total > 0"
        data-testid="docs-badge"
        :tom="docsPendentes ? 'warn' : 'ok'"
      >
        {{
          $t('RAMON.KANBAN.CARD.DOCS', {
            received: lead.docs_received,
            total: lead.docs_total,
          })
        }}
      </Selo>
      <span v-else-if="channelLabel" class="truncate">{{ channelLabel }}</span>
      <span
        v-if="compactValue"
        data-testid="lead-value"
        class="font-mono text-n-slate-11"
      >
        {{ compactValue }}
      </span>
      <Selo
        v-if="prescriptionSelo"
        data-testid="prescription-badge"
        :tom="prescriptionSelo.tom"
      >
        {{ prescriptionSelo.label }}
      </Selo>
      <span
        v-if="contrato"
        data-testid="contrato-limpo-badge"
        :title="$t(`RAMON.CONTRATO.${contrato.key}`, { count: contrato.count })"
        class="i-lucide-badge-check size-3.5"
        :class="contrato.key === 'LIMPO' ? 'text-n-teal-11' : 'text-n-amber-11'"
      />
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="grid place-items-center size-5 ms-auto rounded-full bg-n-slate-3 text-[9.5px] font-semibold text-n-slate-12"
      >
        {{ ownerInitials }}
      </span>
    </div>

    <div
      class="flex items-center gap-3.5 mt-2.5 pt-2 border-t border-n-weak text-xs text-n-slate-11"
    >
      <button
        v-if="slaOverdue && lead.conversation_id"
        data-testid="sla-respond-now"
        class="font-medium text-n-ruby-11 hover:underline"
        @click.stop="emit('openConversation', lead.conversation_id)"
      >
        {{ $t('RAMON.KANBAN.SLA.RESPOND_NOW') }}
      </button>
      <button
        v-if="lead.conversation_id"
        data-testid="open-conversation"
        :class="ACAO"
        @click.stop="emit('openConversation', lead.conversation_id)"
      >
        {{ $t('RAMON.KANBAN.CARD.CONVERSATION') }}
      </button>
      <!-- ganho: cobrar documentos abre a gaveta, onde mora o "Cobrar pendentes" -->
      <template v-if="isWon">
        <button
          v-if="docsPendentes"
          data-testid="charge-docs"
          :class="ACAO"
          @click.stop="emit('openLead', lead)"
        >
          {{ $t('RAMON.KANBAN.CARD.COBRAR_DOCS') }}
        </button>
      </template>
      <template v-else>
        <TaskBellMenu
          :label="$t('RAMON.KANBAN.CARD.FOLLOW_UP')"
          @schedule="onSchedule"
        />
        <button
          data-testid="open-dossie"
          :class="ACAO"
          @click.stop="emit('openDossie', lead)"
        >
          {{ $t('RAMON.KANBAN.CARD.DOSSIE') }}
        </button>
      </template>
    </div>
  </div>
</template>
