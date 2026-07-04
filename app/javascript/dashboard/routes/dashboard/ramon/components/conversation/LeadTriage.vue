<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadTriage' });

const { t } = useI18n();
const triages = ref([]);
const isLoading = ref(false);
const isStarting = ref(false);

const loadTriages = async () => {
  isLoading.value = true;
  try {
    const { data } = await LeadsAPI.getTriages(props.lead.id);
    triages.value = data;
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (props.lead?.id) loadTriages();
});

watch(
  () => props.lead?.latest_triage,
  (next, prev) => {
    if (!next) return;
    if (next.id !== prev?.id || next.status !== prev?.status) loadTriages();
  }
);

const latest = computed(() => triages.value[0] || null);
const older = computed(() => triages.value.slice(1));

const isRunning = computed(() =>
  ['pending', 'running'].includes(latest.value?.status)
);

const runTriage = async () => {
  isStarting.value = true;
  try {
    await LeadsAPI.createTriage(props.lead.id);
    useAlert(t('RAMON.TRIAGE.STARTED'));
    await loadTriages();
  } finally {
    isStarting.value = false;
  }
};

const viabilityClass = viability => {
  if (viability === 'alta') return 'bg-n-teal-3 text-n-teal-11';
  if (viability === 'media') return 'bg-n-amber-3 text-n-amber-11';
  if (viability === 'baixa') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

const viabilityLabelKey = viability =>
  `RAMON.TRIAGE.VIABILITY.${(viability || 'unknown').toUpperCase()}`;

const copyResult = async () => {
  try {
    await copyTextToClipboard(latest.value.result);
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.PLAYBOOK.COPIED'));
};
</script>

<template>
  <div class="flex flex-col gap-4 p-1" data-testid="lead-triage">
    <button
      type="button"
      data-testid="triage-run"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="isRunning || isStarting"
      @click="runTriage"
    >
      {{
        isRunning
          ? $t('RAMON.TRIAGE.RUNNING')
          : $t(latest ? 'RAMON.TRIAGE.RERUN' : 'RAMON.TRIAGE.RUN')
      }}
    </button>

    <p
      v-if="!isLoading && !latest"
      class="text-sm text-n-slate-10"
      data-testid="triage-empty"
    >
      {{ $t('RAMON.TRIAGE.EMPTY') }}
    </p>

    <div
      v-else-if="latest"
      class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="triage-latest"
    >
      <div class="flex items-center justify-between gap-2">
        <span
          data-testid="triage-viability-badge"
          class="inline-block px-2 py-0.5 text-xs rounded-full"
          :class="viabilityClass(latest.viability)"
        >
          {{ $t('RAMON.TRIAGE.VIABILITY.LABEL') }}:
          {{ $t(viabilityLabelKey(latest.viability)) }}
        </span>
        <span
          v-if="latest.triage_agent?.name"
          class="text-xs text-n-slate-10"
        >
          {{ $t('RAMON.TRIAGE.AGENT_LABEL') }}: {{ latest.triage_agent.name }}
        </span>
      </div>

      <p
        v-if="latest.status === 'error'"
        class="text-sm text-n-ruby-11"
        data-testid="triage-error"
      >
        {{ $t('RAMON.TRIAGE.ERROR') }}: {{ latest.error_message }}
      </p>

      <template v-else-if="latest.result">
        <p
          class="text-sm whitespace-pre-wrap text-n-slate-12"
          data-testid="triage-result"
        >
          {{ latest.result }}
        </p>
        <button
          type="button"
          data-testid="triage-copy"
          class="self-start px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @click="copyResult"
        >
          {{ $t('RAMON.PLAYBOOK.COPY') }}
        </button>
      </template>
    </div>

    <div v-if="older.length" class="flex flex-col gap-1">
      <div
        v-for="triage in older"
        :key="triage.id"
        data-testid="triage-old-row"
        class="flex items-center justify-between gap-2 text-xs text-n-slate-10"
      >
        <span>{{ triage.created_at }}</span>
        <span
          class="inline-block px-1.5 py-0.5 rounded-full"
          :class="viabilityClass(triage.viability)"
        >
          {{ $t(viabilityLabelKey(triage.viability)) }}
        </span>
      </div>
    </div>
  </div>
</template>
