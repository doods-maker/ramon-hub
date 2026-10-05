<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';
import ConfirmModal from '../ConfirmModal.vue';
import {
  AVISO,
  CAMPO,
  CARTAO_STATUS,
  FILETE,
  FUNDO_JANELA,
  JANELA,
  RODAPE_JANELA,
  SOBRESCRITO,
  TITULO_JANELA,
  TOM,
} from '../../helpers/ui';

const props = defineProps({ leadId: { type: Number, required: true } });
// rascunho de confirmação nasce nas notas ao remarcar → o painel recarrega
const emit = defineEmits(['notesChanged']);

defineOptions({ name: 'LeadNextAction' });
const store = useStore();
const { t } = useI18n();

const getByLead = useMapGetter('leadTasks/getByLead');
// 1ª tarefa aberta (o getter já ordena por due_at asc).
const task = computed(() => getByLead.value?.(props.leadId)?.[0] ?? null);
const isMeeting = computed(() => task.value?.kind === 'meeting');
// "quinta, 20/08 às 14:00" — reunião mostra quando é, não "em 3 dias".
const meetingWhen = computed(() => {
  if (!isMeeting.value || !task.value?.due_at) return '';
  const d = new Date(task.value.due_at);
  if (Number.isNaN(d.getTime())) return '';
  const dia = d.toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: '2-digit',
  });
  const hora = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${dia} às ${hora}`;
});

const load = id => {
  if (id) store?.dispatch('leadTasks/fetchForLead', id);
};
onMounted(() => load(props.leadId));
watch(
  () => props.leadId,
  id => load(id)
);

// mesmo cálculo relativo do LeadTasksList: dias inteiros entre meia-noites
const dueInfo = computed(() => {
  if (!task.value?.due_at) return { text: '', overdue: false };
  const startOf = ts => {
    const d = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };
  const days = Math.round(
    (startOf(task.value.due_at) - startOf(Date.now())) / 86400000
  );
  if (days < 0) return { text: t('RAMON.TASKS.OVERDUE'), overdue: true };
  if (days === 0) return { text: t('RAMON.TASKS.TODAY'), overdue: false };
  return { text: t('RAMON.TASKS.IN_DAYS', { n: days }), overdue: false };
});

// guard único para Feito/Adiar/Reagendar: um voo por vez
const busy = ref(false);
const run = async fn => {
  if (busy.value) return;
  busy.value = true;
  try {
    await fn();
  } catch (e) {
    useAlert(t('RAMON.LEAD_PANEL.NEXT_ACTION.ERROR'));
  } finally {
    busy.value = false;
  }
};

const complete = () =>
  run(() =>
    store.dispatch('leadTasks/complete', {
      leadId: props.leadId,
      taskId: task.value.id,
    })
  );

// Adiar 1d: soma 24h ao due_at atual (sem prazo, parte de agora).
const snooze = () =>
  run(() => {
    const base = task.value.due_at ? new Date(task.value.due_at) : new Date();
    return store.dispatch('leadTasks/update', {
      leadId: props.leadId,
      taskId: task.value.id,
      payload: { due_at: new Date(base.getTime() + 86400000).toISOString() },
    });
  });

// ----- Reunião: não se adia — Remarcar passa pelo agendamento (lembretes do
// horário novo, atividade de→para, novo rascunho de confirmação, sino).
// Reunião do Cal.com: o hub não mexe no Cal.com — avisa pra remarcar lá.
const isCalcom = computed(() =>
  Boolean(task.value?.title?.startsWith('Reunião Cal.com'))
);
// datetime-local trabalha em hora local (YYYY-MM-DDTHH:mm)
const paraCampo = date =>
  new Date(date.getTime() - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
const remarcarAberto = ref(false);
const novoHorario = ref('');
const minHorario = ref('');
const abrirRemarcar = () => {
  novoHorario.value = paraCampo(new Date(task.value.due_at));
  minHorario.value = paraCampo(new Date());
  remarcarAberto.value = true;
};
const remarcar = () =>
  run(async () => {
    if (!novoHorario.value) return;
    await store.dispatch('leadTasks/remarcarReuniao', {
      leadId: props.leadId,
      taskId: task.value.id,
      startsAt: new Date(novoHorario.value).toISOString(),
    });
    remarcarAberto.value = false;
    emit('notesChanged');
    useAlert(t('RAMON.LEAD_PANEL.NEXT_ACTION.REMARCADA'));
  });

// ----- "Feito" numa reunião: como foi? Qualificada/Não qualificada registram
// o resultado (mesma regra do Andamento: só o Closer do lead, o time closer
// com lead sem Closer, ou o gestor) e concluem a tarefa; Não compareceu
// conclui com no-show, sem resultado (o prêmio do SDR só conta qualificada).
const role = useMapGetter('getCurrentRole');
const meuId = useMapGetter('getCurrentUserID');
const podeRegistrar = computed(() => {
  if (role.value === 'administrator') return true;
  const closerId = task.value?.closer_id;
  return !closerId || closerId === meuId.value;
});
const resultadoAberto = ref(false);
const registrarResultado = resultado =>
  run(async () => {
    resultadoAberto.value = false;
    await store.dispatch('leads/registrarReuniao', {
      id: props.leadId,
      resultado,
      taskId: task.value.id,
    });
  });
const naoCompareceu = () =>
  run(async () => {
    resultadoAberto.value = false;
    await store.dispatch('leadTasks/complete', {
      leadId: props.leadId,
      taskId: task.value.id,
      resultado: 'nao_compareceu',
    });
  });
const onDone = () => {
  if (isMeeting.value) resultadoAberto.value = true;
  else complete();
};

// Cancelar: mesmo efeito do cancel do Cal.com (atividade + sino); nada vai ao
// cliente. Os lembretes já enfileirados morrem no guard do job.
const cancelarAberto = ref(false);
const cancelar = () =>
  run(async () => {
    cancelarAberto.value = false;
    await store.dispatch('leadTasks/cancelarReuniao', {
      leadId: props.leadId,
      taskId: task.value.id,
    });
    useAlert(t('RAMON.LEAD_PANEL.NEXT_ACTION.CANCELADA'));
  });
const mensagemCancelar = computed(() =>
  [
    t('RAMON.LEAD_PANEL.NEXT_ACTION.CANCELAR_CONFIRM', {
      quando: meetingWhen.value,
    }),
    isCalcom.value ? t('RAMON.LEAD_PANEL.NEXT_ACTION.CALCOM_CANCELAR') : '',
  ]
    .filter(Boolean)
    .join(' ')
);

// Reagendar via TaskBellMenu: só a data muda — o título da tarefa fica.
const reschedule = ({ dueAt }) =>
  run(() =>
    store.dispatch('leadTasks/update', {
      leadId: props.leadId,
      taskId: task.value.id,
      payload: { due_at: dueAt },
    })
  );
</script>

<template>
  <div
    v-if="task"
    data-testid="lead-next-action"
    :class="[CARTAO_STATUS, dueInfo.overdue ? FILETE.amber : FILETE.blue]"
  >
    <p
      :class="[
        SOBRESCRITO,
        dueInfo.overdue
          ? 'text-n-amber-11'
          : isMeeting
            ? 'text-n-blue-11'
            : 'text-n-slate-10',
      ]"
    >
      <template v-if="isMeeting">
        <span
          class="i-lucide-calendar-clock inline-block size-3 align-[-2px]"
        />
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.MEETING_TITLE') }}
      </template>
      <template v-else>{{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.TITLE') }}</template>
      <template v-if="dueInfo.text">· {{ dueInfo.text }}</template>
    </p>
    <p
      v-if="isMeeting && meetingWhen"
      data-testid="next-action-meeting-when"
      class="mt-1 font-mono text-sm font-semibold text-n-slate-12 capitalize"
    >
      {{ meetingWhen }}
    </p>
    <p
      class="text-sm text-n-slate-12"
      :class="isMeeting ? 'text-xs text-n-slate-11' : 'mt-1'"
    >
      {{ task.title }}
    </p>
    <router-link
      v-if="isMeeting"
      v-slot="{ navigate }"
      custom
      :to="{ name: 'ramon_agenda' }"
    >
      <Button
        data-testid="next-action-agenda-link"
        link
        xs
        class="mt-1"
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.SEE_AGENDA')"
        @click="navigate"
      />
    </router-link>
    <div class="flex items-center gap-1.5 mt-2.5">
      <Button
        data-testid="next-action-done"
        sm
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.DONE')"
        :disabled="busy"
        @click="onDone"
      />
      <Button
        v-if="isMeeting"
        data-testid="next-action-remarcar"
        sm
        faded
        slate
        icon="i-lucide-calendar-sync"
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.REMARCAR')"
        :disabled="busy"
        @click="abrirRemarcar"
      />
      <Button
        v-if="isMeeting"
        data-testid="next-action-cancelar"
        sm
        ghost
        ruby
        icon="i-lucide-calendar-x"
        :title="$t('RAMON.LEAD_PANEL.NEXT_ACTION.CANCELAR')"
        :disabled="busy"
        @click="cancelarAberto = true"
      />
      <template v-else>
        <Button
          data-testid="next-action-snooze"
          sm
          faded
          slate
          :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.SNOOZE')"
          :disabled="busy"
          @click="snooze"
        />
        <span
          class="flex items-center gap-1 text-xs text-n-slate-11"
          data-testid="next-action-reschedule"
        >
          {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.RESCHEDULE') }}
          <TaskBellMenu @schedule="reschedule" />
        </span>
      </template>
    </div>

    <Teleport to="body">
      <div
        v-if="resultadoAberto"
        :class="FUNDO_JANELA"
        @click.self="resultadoAberto = false"
      >
        <div :class="JANELA" data-testid="resultado-janela">
          <h3 :class="TITULO_JANELA">
            {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.RESULTADO_TITULO') }}
          </h3>
          <p class="mb-3 text-xs text-n-slate-10">
            {{ task.title
            }}<template v-if="meetingWhen">
              · <span class="font-mono">{{ meetingWhen }}</span>
            </template>
          </p>
          <div class="flex flex-col gap-2">
            <Button
              data-testid="resultado-qualificada"
              sm
              teal
              icon="i-lucide-check"
              :label="$t('RAMON.REUNIAO.QUALIFICADA')"
              :disabled="busy || !podeRegistrar"
              @click="registrarResultado('qualificada')"
            />
            <Button
              data-testid="resultado-nao-qualificada"
              sm
              faded
              slate
              :label="$t('RAMON.REUNIAO.NAO_QUALIFICADA')"
              :disabled="busy || !podeRegistrar"
              @click="registrarResultado('nao_qualificada')"
            />
            <Button
              data-testid="resultado-nao-compareceu"
              sm
              faded
              amber
              icon="i-lucide-user-x"
              :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.NAO_COMPARECEU')"
              :disabled="busy"
              @click="naoCompareceu"
            />
          </div>
          <p
            v-if="!podeRegistrar"
            data-testid="resultado-so-closer"
            class="mt-3 mb-0 text-xs text-n-slate-10"
          >
            {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.SO_CLOSER') }}
          </p>
          <div :class="RODAPE_JANELA">
            <Button
              sm
              ghost
              slate
              :label="$t('RAMON.MODAL.CANCEL')"
              @click="resultadoAberto = false"
            />
          </div>
        </div>
      </div>
      <ConfirmModal
        v-if="cancelarAberto"
        :title="$t('RAMON.LEAD_PANEL.NEXT_ACTION.CANCELAR')"
        :message="mensagemCancelar"
        :confirm-label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.CANCELAR')"
        @confirm="cancelar"
        @cancel="cancelarAberto = false"
      />
      <div
        v-if="remarcarAberto"
        :class="FUNDO_JANELA"
        @click.self="remarcarAberto = false"
      >
        <div :class="JANELA" data-testid="remarcar-janela">
          <h3 :class="TITULO_JANELA">
            {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.REMARCAR_TITULO') }}
          </h3>
          <p class="mb-3 text-xs text-n-slate-10">{{ task.title }}</p>
          <input
            v-model="novoHorario"
            data-testid="remarcar-data"
            type="datetime-local"
            :min="minHorario"
            :class="CAMPO"
            class="font-mono"
          />
          <p
            v-if="isCalcom"
            data-testid="remarcar-calcom"
            :class="[AVISO, TOM.amber]"
            class="mt-3 mb-0"
          >
            {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.CALCOM_REMARCAR') }}
          </p>
          <p class="mt-3 mb-0 text-xs text-n-slate-10">
            {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.REMARCAR_HINT') }}
          </p>
          <div :class="RODAPE_JANELA">
            <Button
              sm
              faded
              slate
              :label="$t('RAMON.MODAL.CANCEL')"
              @click="remarcarAberto = false"
            />
            <Button
              data-testid="remarcar-confirmar"
              sm
              :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.REMARCAR')"
              :disabled="busy || !novoHorario"
              @click="remarcar"
            />
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
