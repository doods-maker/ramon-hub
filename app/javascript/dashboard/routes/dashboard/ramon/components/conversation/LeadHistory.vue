<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { formatBrl } from 'dashboard/routes/dashboard/ramon/helpers/currency';

const props = defineProps({
  leadId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadHistory' });

const store = useStore();
const { t, te } = useI18n();
const activities = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const load = async () => {
  // zera antes de buscar: nunca mostrar a timeline do lead anterior
  activities.value = [];
  isLoading.value = true;
  hasError.value = false;
  try {
    activities.value = await store.dispatch(
      'leads/fetchActivities',
      Number(props.leadId)
    );
  } catch (e) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};
watch(() => props.leadId, load, { immediate: true });

// mais recente no topo
const ordered = computed(() => [...activities.value].reverse());

const labelKey = kind => `RAMON.LEAD_PANEL.HISTORY.KIND.${kind.toUpperCase()}`;

// kind desconhecido não vaza chave crua (padrão do Dossie)
const label = kind => {
  const key = labelKey(kind);
  return te(key) ? t(key) : kind;
};

const detail = activity => {
  let text = ` · ${label(activity.kind)}`;
  if (activity.to_value) {
    const toValue =
      activity.kind === 'value_changed'
        ? formatBrl(activity.to_value)
        : activity.to_value;
    text += ` → ${toValue}`;
  }
  return text;
};

// mesma máscara do fmtDateTime do Dossie.vue
const fmtDateTime = value => {
  if (!value) return '';
  return new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
</script>

<template>
  <div class="flex flex-col gap-3 p-1">
    <p
      v-if="isLoading"
      data-testid="history-loading"
      class="text-xs text-n-slate-9"
    >
      {{ $t('RAMON.LEAD_PANEL.HISTORY.LOADING') }}
    </p>
    <template v-else-if="hasError">
      <p data-testid="history-error" class="text-xs text-n-ruby-11">
        {{ $t('RAMON.LEAD_PANEL.HISTORY.LOAD_ERROR') }}
      </p>
      <button
        data-testid="history-retry"
        class="self-start text-xs text-n-iris-11 hover:underline"
        @click="load"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </template>
    <p
      v-else-if="!ordered.length"
      data-testid="history-empty"
      class="text-xs text-n-slate-9"
    >
      {{ $t('RAMON.LEAD_PANEL.HISTORY.EMPTY') }}
    </p>
    <div
      v-for="activity in ordered"
      :key="activity.id"
      data-testid="activity-row"
      class="flex flex-col gap-0.5 border-l-2 border-n-weak pl-3"
    >
      <span class="text-sm text-n-slate-12">
        <strong v-if="activity.author_name">{{ activity.author_name }}</strong>
        <span v-else>{{ $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM') }}</span>
        <span>{{ detail(activity) }}</span>
      </span>
      <span class="text-xs text-n-slate-10">{{
        fmtDateTime(activity.created_at)
      }}</span>
    </div>
  </div>
</template>
