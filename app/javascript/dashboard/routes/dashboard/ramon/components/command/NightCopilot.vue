<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// "Enquanto você dormia" (mock 4b): sugestões do copiloto noturno no topo do
// Cockpit. Nada é enviado ao cliente — aplicar rascunho vira NOTA no lead.
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const suggestions = computed(
  () => getters['copilotSuggestions/getSuggestions'].value
);
const meta = computed(() => getters['copilotSuggestions/getMeta'].value);
const uiFlags = computed(() => getters['copilotSuggestions/getUIFlags'].value);

onMounted(() => store.dispatch('copilotSuggestions/fetch'));

// "Aprovar todas" cobre só draft/alert — move_stage é cartão a cartão.
const bulkCount = computed(
  () => suggestions.value.filter(s => s.kind !== 'move_stage').length
);

const runTime = computed(() => {
  const withRun = suggestions.value.find(s => s.run_at);
  if (!withRun) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(withRun.run_at));
});

const TAGS = {
  draft: {
    label: 'RAMON.NIGHT_COPILOT.TAG_DRAFT',
    class: 'bg-[#c9a97c]/[.16] text-n-iris-11',
  },
  move_stage: {
    label: 'RAMON.NIGHT_COPILOT.TAG_MOVE_STAGE',
    class: 'bg-n-amber-3 text-n-amber-11',
  },
  alert: {
    label: 'RAMON.NIGHT_COPILOT.TAG_ALERT',
    class: 'bg-n-ruby-3 text-n-ruby-11',
  },
};
const tagFor = kind => TAGS[kind] || TAGS.alert;

const bodyText = s =>
  s.kind === 'draft'
    ? `"${s.payload.texto || ''}"`
    : s.payload.justificativa || '';

// Guard de duplo-clique por cartão.
const actingId = ref(null);
const isBulkActing = ref(false);

const apply = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('copilotSuggestions/apply', suggestion.id);
    useAlert(t('RAMON.NIGHT_COPILOT.APPLIED'));
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const dismiss = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('copilotSuggestions/dismiss', suggestion.id);
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

// Alerta → tarefa follow_up pra hoje (Esteira) + marca como aplicada.
const escalate = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('leadTasks/create', {
      leadId: suggestion.lead_id,
      title: t('RAMON.NIGHT_COPILOT.ESCALATE_TASK_TITLE'),
      kind: 'follow_up',
      dueAt: new Date(new Date().setHours(23, 59, 0, 0)).toISOString(),
    });
    await store.dispatch('copilotSuggestions/apply', suggestion.id);
    useAlert(t('RAMON.NIGHT_COPILOT.ESCALATED'));
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const applyAll = async () => {
  if (isBulkActing.value) return;
  isBulkActing.value = true;
  try {
    await store.dispatch('copilotSuggestions/applyAll');
    useAlert(t('RAMON.NIGHT_COPILOT.APPLIED_ALL'));
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    isBulkActing.value = false;
  }
};

const retry = () => store.dispatch('copilotSuggestions/fetch');
</script>

<template>
  <!-- Erro de carga: retry explícito em vez de sumir calado -->
  <div
    v-if="uiFlags.hasError"
    data-testid="night-copilot-error"
    class="p-4 rounded-[14px] border border-n-weak bg-n-solid-2 text-sm"
  >
    <p class="text-n-ruby-11">{{ t('RAMON.NIGHT_COPILOT.LOAD_ERROR') }}</p>
    <button
      type="button"
      data-testid="night-copilot-retry"
      class="mt-1 text-xs text-n-iris-11 hover:underline"
      @click="retry"
    >
      {{ t('RAMON.NIGHT_COPILOT.RETRY') }}
    </button>
  </div>

  <!-- Bloco some quando não há sugestão pendente -->
  <section
    v-else-if="suggestions.length"
    data-testid="night-copilot"
    class="p-5 rounded-[14px] border border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center gap-2.5 mb-3.5">
      <span
        class="flex items-center justify-center flex-none rounded-[10px] size-[34px] bg-gradient-to-br from-[#463528] to-[#8a5c33]"
      >
        <span class="i-lucide-bot size-[17px] text-n-slate-12" />
      </span>
      <div class="min-w-0">
        <p class="text-sm font-semibold text-n-slate-12">
          {{ t('RAMON.NIGHT_COPILOT.TITLE') }}
        </p>
        <p class="text-[11px] text-n-slate-10 truncate">
          {{
            t('RAMON.NIGHT_COPILOT.SUBTITLE', {
              leads: meta.reviewedCount,
              time: runTime,
              count: suggestions.length,
            })
          }}
        </p>
      </div>
      <button
        v-if="bulkCount"
        type="button"
        data-testid="night-copilot-apply-all"
        class="ml-auto px-3.5 py-[7px] text-xs font-semibold rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
        :disabled="isBulkActing"
        @click="applyAll"
      >
        {{ t('RAMON.NIGHT_COPILOT.APPROVE_ALL', { count: bulkCount }) }}
      </button>
    </div>

    <div class="flex flex-col gap-2">
      <div
        v-for="suggestion in suggestions"
        :key="suggestion.id"
        data-testid="night-copilot-card"
        class="px-3.5 py-3 rounded-[11px] bg-n-solid-2 border"
        :class="
          suggestion.kind === 'alert'
            ? 'border-n-ruby-5'
            : 'border-[#c9a97c]/[.12]'
        "
      >
        <div class="flex items-center gap-2">
          <span
            class="px-2 py-0.5 text-[9.5px] font-semibold rounded-full uppercase tracking-[.06em]"
            :class="tagFor(suggestion.kind).class"
          >
            {{ t(tagFor(suggestion.kind).label) }}
          </span>
          <p class="text-[13px] font-medium text-n-slate-12 truncate">
            {{ suggestion.lead_name }}
          </p>
          <span
            v-if="suggestion.payload.days_stalled"
            class="ml-auto text-[10.5px] text-n-slate-9 flex-none"
          >
            {{
              t('RAMON.NIGHT_COPILOT.STALLED_FOR', {
                days: suggestion.payload.days_stalled,
              })
            }}
          </span>
        </div>

        <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
          {{ bodyText(suggestion) }}
          <b
            v-if="suggestion.kind === 'move_stage'"
            class="font-semibold text-n-slate-12"
          >
            {{
              t('RAMON.NIGHT_COPILOT.MOVE_TO', {
                stage: suggestion.payload.etapa_sugerida,
              })
            }}
          </b>
        </p>

        <div class="flex gap-1.5 mt-2">
          <template v-if="suggestion.kind === 'draft'">
            <button
              type="button"
              data-testid="night-copilot-apply"
              class="px-3 py-1 text-[11px] font-semibold rounded-[7px] bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4 disabled:opacity-50"
              :disabled="actingId === suggestion.id"
              @click="apply(suggestion)"
            >
              {{ t('RAMON.NIGHT_COPILOT.SAVE_NOTE') }}
            </button>
          </template>
          <template v-else-if="suggestion.kind === 'move_stage'">
            <button
              type="button"
              data-testid="night-copilot-apply"
              class="px-3 py-1 text-[11px] font-semibold rounded-[7px] bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4 disabled:opacity-50"
              :disabled="actingId === suggestion.id"
              @click="apply(suggestion)"
            >
              {{ t('RAMON.NIGHT_COPILOT.APPLY') }}
            </button>
          </template>
          <template v-else>
            <button
              type="button"
              data-testid="night-copilot-apply"
              class="px-3 py-1 text-[11px] font-semibold rounded-[7px] bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 disabled:opacity-50"
              :disabled="actingId === suggestion.id"
              @click="apply(suggestion)"
            >
              {{ t('RAMON.NIGHT_COPILOT.OK') }}
            </button>
            <button
              type="button"
              data-testid="night-copilot-escalate"
              class="px-3 py-1 text-[11px] font-semibold rounded-[7px] bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
              :disabled="actingId === suggestion.id"
              @click="escalate(suggestion)"
            >
              {{ t('RAMON.NIGHT_COPILOT.ESCALATE') }}
            </button>
          </template>
          <button
            v-if="suggestion.kind !== 'alert'"
            type="button"
            data-testid="night-copilot-dismiss"
            class="px-3 py-1 text-[11px] rounded-[7px] text-n-slate-9 hover:text-n-slate-11 disabled:opacity-50"
            :disabled="actingId === suggestion.id"
            @click="dismiss(suggestion)"
          >
            {{ t('RAMON.NIGHT_COPILOT.DISMISS') }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>
