<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

// Smart Views ficam em ui_settings.ramon_lead_views (sem backend próprio),
// no mesmo mecanismo dos atalhos externos: [{ name, filters }].
const views = computed(() => uiSettings.value?.ramon_lead_views ?? []);
const leads = computed(() => getters['leads/getLeads']?.value ?? []);
const currentFilters = computed(() => getters['leads/getFilters']?.value ?? {});

const eq = (a, b) => String(a) === String(b);

// Contador client-side sobre os leads já carregados. A busca textual (q) NÃO
// entra aqui — o texto é resolvido server-side e não temos como reproduzi-lo.
const matchesFilters = (lead, filters = {}) => {
  if (filters.leadStageId && !eq(lead.lead_stage_id, filters.leadStageId))
    return false;
  if (filters.benefitTypeId && !eq(lead.benefit_type_id, filters.benefitTypeId))
    return false;
  if (
    filters.leadPriorityId &&
    !eq(lead.lead_priority_id, filters.leadPriorityId)
  )
    return false;
  if (filters.source && !eq(lead.source, filters.source)) return false;
  if (filters.stalled && !lead.stalled) return false;
  if (filters.noOpenTask && lead.open_tasks_count !== 0) return false;
  // created_at é ISO; comparar só a data (YYYY-MM-DD) evita ruído de fuso.
  const leadDate = lead.created_at ? lead.created_at.slice(0, 10) : null;
  if (filters.createdAfter && (!leadDate || leadDate < filters.createdAfter))
    return false;
  if (filters.createdBefore && (!leadDate || leadDate > filters.createdBefore))
    return false;
  return true;
};

const countFor = filters =>
  leads.value.filter(lead => matchesFilters(lead, filters)).length;

const applyView = view => {
  // filters da view é o snapshot completo dos filtros → o merge do setFilters
  // equivale a substituir tudo, zerando o que a view não define.
  store.dispatch('leads/setFilters', { ...view.filters });
};

const saveCurrentView = () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(t('RAMON.FUNIL.VIEWS.SAVE_PROMPT'));
  if (!name || !name.trim()) return;
  const next = [
    ...views.value,
    { name: name.trim(), filters: { ...currentFilters.value } },
  ];
  updateUISettings({ ramon_lead_views: next });
};

const removeView = index => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAMON.FUNIL.VIEWS.REMOVE_CONFIRM'))) return;
  const next = views.value.filter((_, i) => i !== index);
  updateUISettings({ ramon_lead_views: next });
};
</script>

<template>
  <div
    v-if="views.length"
    class="flex flex-wrap items-center gap-2 px-4 pt-2"
    data-testid="saved-views"
  >
    <div
      v-for="(view, index) in views"
      :key="index"
      class="flex items-center rounded-full bg-n-alpha-2 text-n-slate-12"
    >
      <button
        data-testid="saved-view-chip"
        class="flex items-center gap-1.5 py-1 pl-3 pr-1.5 text-sm rounded-l-full hover:bg-n-alpha-3"
        @click="applyView(view)"
      >
        <span>{{ view.name }}</span>
        <span class="text-xs text-n-slate-11">{{ countFor(view.filters) }}</span>
      </button>
      <button
        data-testid="saved-view-remove"
        class="flex items-center pr-2 pl-1 text-n-slate-10 hover:text-n-slate-12"
        :aria-label="$t('RAMON.FUNIL.VIEWS.REMOVE')"
        :title="$t('RAMON.FUNIL.VIEWS.REMOVE')"
        @click="removeView(index)"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>
    <button
      data-testid="saved-view-add"
      class="flex items-center gap-1 px-3 py-1 text-sm rounded-full text-n-slate-11 border border-dashed border-n-weak hover:text-n-slate-12"
      @click="saveCurrentView"
    >
      <span class="i-lucide-plus size-3.5" />{{ $t('RAMON.FUNIL.VIEWS.SAVE') }}
    </button>
  </div>
  <div v-else class="flex items-center px-4 pt-2" data-testid="saved-views">
    <button
      data-testid="saved-view-add"
      class="flex items-center gap-1 px-3 py-1 text-sm rounded-full text-n-slate-11 border border-dashed border-n-weak hover:text-n-slate-12"
      @click="saveCurrentView"
    >
      <span class="i-lucide-plus size-3.5" />{{ $t('RAMON.FUNIL.VIEWS.SAVE') }}
    </button>
  </div>
</template>
