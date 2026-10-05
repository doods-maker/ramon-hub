<script setup>
import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, SELECT } from '../../helpers/ui';

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

// Contorno azul destaca o controle com filtro ativo. !w-44: o kit é w-full e
// cada controle viraria uma linha inteira (paredão de filtros).
const ctl = `${SELECT} !w-44`;
const activeClass = value => (value ? '!outline-n-blue-8' : '');

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

// A busca (q) fica no header do board; o Limpar daqui também a zera.
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
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-4 py-2">
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
      class="flex items-center gap-1.5 mb-0 text-xs font-normal leading-normal whitespace-nowrap"
      :class="filters.createdAfter ? 'text-n-blue-11' : 'text-n-slate-10'"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CREATED_AFTER') }}
      <input
        type="date"
        data-testid="filter-created-after"
        class="!w-36 font-mono"
        :class="[CAMPO, activeClass(filters.createdAfter)]"
        :value="filters.createdAfter || ''"
        @change="emitUpdate({ createdAfter: $event.target.value || null })"
      />
    </label>
    <label
      class="flex items-center gap-1.5 mb-0 text-xs font-normal leading-normal whitespace-nowrap"
      :class="filters.createdBefore ? 'text-n-blue-11' : 'text-n-slate-10'"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CREATED_BEFORE') }}
      <input
        type="date"
        data-testid="filter-created-before"
        class="!w-36 font-mono"
        :class="[CAMPO, activeClass(filters.createdBefore)]"
        :value="filters.createdBefore || ''"
        @change="emitUpdate({ createdBefore: $event.target.value || null })"
      />
    </label>
    <label
      class="flex items-center gap-1.5 px-2 py-1.5 mb-0 text-sm font-normal leading-normal rounded-lg cursor-pointer"
      :class="
        filters.stalled
          ? 'text-n-blue-11'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      <input
        type="checkbox"
        class="m-0 accent-n-brand"
        data-testid="filter-stalled"
        :checked="!!filters.stalled"
        @change="emitUpdate({ stalled: $event.target.checked })"
      />
      {{ $t('RAMON.FUNIL.FILTERS.STALLED') }}
    </label>
    <label
      class="flex items-center gap-1.5 px-2 py-1.5 mb-0 text-sm font-normal leading-normal rounded-lg cursor-pointer"
      :class="
        filters.noOpenTask
          ? 'text-n-blue-11'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      <input
        type="checkbox"
        class="m-0 accent-n-brand"
        data-testid="filter-no-open-task"
        :checked="!!filters.noOpenTask"
        @change="emitUpdate({ noOpenTask: $event.target.checked })"
      />
      {{ $t('RAMON.FUNIL.FILTERS.NO_OPEN_TASK') }}
    </label>
    <Button
      v-if="hasActive"
      data-testid="filter-clear"
      sm
      ghost
      slate
      icon="i-lucide-x"
      :label="$t('RAMON.FUNIL.FILTERS.CLEAR')"
      @click="clearFilters"
    />
  </div>
</template>
