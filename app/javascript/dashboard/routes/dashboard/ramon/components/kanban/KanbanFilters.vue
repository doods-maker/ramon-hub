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
const channels = computed(() => getters['leadConfig/getChannels'].value);
const agents = computed(() => getters['agents/getAgents'].value);
// getter pode não existir em cenários de teste isolados — cai para lista vazia.
const stages = computed(() => getters['leadConfig/getStages']?.value ?? []);

const emitUpdate = partial => emit('update', partial);

// Borda destaca o controle com filtro ativo; transparente mantém o tamanho.
// w-44 explícito: o CSS global do Chatwoot põe width:100% em select/input e
// cada controle viraria uma linha inteira (paredão de filtros).
const ctl =
  'w-44 px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 border text-n-slate-12 outline-none focus:border-n-slate-8';
const activeClass = value => (value ? 'border-n-iris-8' : 'border-transparent');

const hasActive = computed(() => {
  const f = props.filters;
  return !!(
    f.q ||
    f.benefitTypeId ||
    f.leadPriorityId ||
    f.agentId ||
    f.source ||
    f.channel ||
    f.leadStageId ||
    f.createdAfter ||
    f.createdBefore ||
    f.stalled ||
    f.noOpenTask
  );
});

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
    channel: '',
    q: '',
    leadStageId: null,
    createdAfter: null,
    createdBefore: null,
    stalled: false,
    noOpenTask: false,
  });
  search.value = '';
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-4 py-2">
    <input
      v-model="search"
      data-testid="filter-search"
      class="w-56 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border text-n-slate-12 outline-none focus:border-n-slate-8"
      :class="activeClass(filters.q)"
      :placeholder="$t('RAMON.FUNIL.FILTERS.SEARCH')"
    />
    <select
      data-testid="filter-benefit"
      :class="[ctl, activeClass(filters.benefitTypeId)]"
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
      :class="[ctl, activeClass(filters.leadPriorityId)]"
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
      :class="[ctl, activeClass(filters.agentId)]"
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
      :class="[ctl, activeClass(filters.source)]"
      :value="filters.source || ''"
      @change="emitUpdate({ source: $event.target.value || '' })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.SOURCE') }}</option>
      <option v-for="s in sources" :key="s" :value="s">{{ s }}</option>
    </select>
    <select
      data-testid="filter-channel"
      :class="[ctl, activeClass(filters.channel)]"
      :value="filters.channel || ''"
      @change="emitUpdate({ channel: $event.target.value || '' })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.CHANNEL') }}</option>
      <option v-for="c in channels" :key="c.key" :value="c.key">
        {{ c.label }}
      </option>
    </select>
    <select
      data-testid="filter-stage"
      :class="[ctl, activeClass(filters.leadStageId)]"
      :value="filters.leadStageId || ''"
      @change="emitUpdate({ leadStageId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.STAGE') }}</option>
      <option v-for="st in stages" :key="st.id" :value="st.id">
        {{ st.name }}
      </option>
    </select>
    <label
      class="flex items-center gap-1.5 text-xs whitespace-nowrap text-n-slate-10"
      :class="{ 'text-n-iris-11': filters.createdAfter }"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CREATED_AFTER') }}
      <input
        type="date"
        data-testid="filter-created-after"
        :class="[ctl, activeClass(filters.createdAfter)]"
        :value="filters.createdAfter || ''"
        @change="emitUpdate({ createdAfter: $event.target.value || null })"
      />
    </label>
    <label
      class="flex items-center gap-1.5 text-xs whitespace-nowrap text-n-slate-10"
      :class="{ 'text-n-iris-11': filters.createdBefore }"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CREATED_BEFORE') }}
      <input
        type="date"
        data-testid="filter-created-before"
        :class="[ctl, activeClass(filters.createdBefore)]"
        :value="filters.createdBefore || ''"
        @change="emitUpdate({ createdBefore: $event.target.value || null })"
      />
    </label>
    <label
      class="flex items-center gap-1.5 px-2 py-1.5 text-sm rounded-lg cursor-pointer"
      :class="
        filters.stalled
          ? 'text-n-iris-11'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      <input
        type="checkbox"
        data-testid="filter-stalled"
        :checked="!!filters.stalled"
        @change="emitUpdate({ stalled: $event.target.checked })"
      />
      {{ $t('RAMON.FUNIL.FILTERS.STALLED') }}
    </label>
    <label
      class="flex items-center gap-1.5 px-2 py-1.5 text-sm rounded-lg cursor-pointer"
      :class="
        filters.noOpenTask
          ? 'text-n-iris-11'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      <input
        type="checkbox"
        data-testid="filter-no-open-task"
        :checked="!!filters.noOpenTask"
        @change="emitUpdate({ noOpenTask: $event.target.checked })"
      />
      {{ $t('RAMON.FUNIL.FILTERS.NO_OPEN_TASK') }}
    </label>
    <button
      v-if="hasActive"
      data-testid="filter-clear"
      class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
      @click="clearFilters"
    >
      <span class="i-lucide-x size-3.5" />
      {{ $t('RAMON.FUNIL.FILTERS.CLEAR') }}
    </button>
  </div>
</template>
