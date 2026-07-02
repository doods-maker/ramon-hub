<script setup>
import { ref, computed, watch } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';

const props = defineProps({
  filters: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const getters = useStoreGetters();
const benefitTypes = computed(
  () => getters['leadConfig/getBenefitTypes'].value
);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const sources = computed(() => getters['leadConfig/getSources'].value);
const agents = computed(() => getters['agents/getAgents'].value);

const emitUpdate = partial => emit('update', partial);

// Busca com debounce ~300ms para não disparar um request por tecla.
const search = ref(props.filters.q);
let timer = null;
watch(search, value => {
  clearTimeout(timer);
  if (value === props.filters.q) return;
  timer = setTimeout(() => emitUpdate({ q: value }), 300);
});
// loadFilters restaura o q persistido depois do setup — refletir na caixa
watch(
  () => props.filters.q,
  value => {
    if (value !== search.value) search.value = value ?? '';
  }
);

const clearFilters = () => {
  emitUpdate({
    benefitTypeId: null,
    leadPriorityId: null,
    agentId: null,
    source: '',
    q: '',
  });
  search.value = '';
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-4 py-2">
    <input
      v-model="search"
      data-testid="filter-search"
      class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :placeholder="$t('RAMON.FUNIL.FILTERS.SEARCH')"
    />
    <select
      data-testid="filter-benefit"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.benefitTypeId || ''"
      @change="emitUpdate({ benefitTypeId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.BENEFIT') }}</option>
      <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
        {{ b.name }}
      </option>
    </select>
    <select
      data-testid="filter-priority"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.leadPriorityId || ''"
      @change="emitUpdate({ leadPriorityId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.PRIORITY') }}</option>
      <option v-for="p in priorities" :key="p.id" :value="p.id">
        {{ p.name }}
      </option>
    </select>
    <select
      data-testid="filter-agent"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.agentId || ''"
      @change="emitUpdate({ agentId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.AGENT') }}</option>
      <option v-for="a in agents" :key="a.id" :value="a.id">
        {{ a.name }}
      </option>
    </select>
    <select
      data-testid="filter-source"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.source || ''"
      @change="emitUpdate({ source: $event.target.value || '' })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.SOURCE') }}</option>
      <option v-for="s in sources" :key="s" :value="s">{{ s }}</option>
    </select>
    <button
      data-testid="filter-clear"
      class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
      @click="clearFilters"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CLEAR') }}
    </button>
  </div>
</template>
