<script setup>
import { computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'ColheitaChecklist' });

const store = useStore();
const theses = useMapGetter('theses/getTheses');

const thesis = computed(() =>
  theses.value.find(x => x.id === props.lead?.thesis_id)
);

// garante que os itens da tese estejam carregados (mesmo padrão do DocChecklist)
const ensureItems = async () => {
  const thesisId = props.lead?.thesis_id;
  if (!thesisId) return;
  const current = theses.value.find(x => x.id === thesisId);
  if (!current || !current.items) {
    await store.dispatch('theses/show', thesisId);
  }
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

const colheitaItems = computed(() =>
  (thesis.value?.items || []).filter(item => item.section === 'colheita')
);

// mapa { "<item_id>": true } vindo de custom_attributes.colheita_status
const colheitaStatus = computed(
  () => props.lead?.custom_attributes?.colheita_status || {}
);

const isDone = item => Boolean(colheitaStatus.value[item.id]);

const doneCount = computed(() => colheitaItems.value.filter(isDone).length);

// grava o colheita_status novo mesclando com o custom_attributes existente,
// sem sobrescrever nenhuma outra chave.
const toggle = item => {
  const next = { ...colheitaStatus.value };
  if (next[item.id]) delete next[item.id];
  else next[item.id] = true;
  store.dispatch('leads/update', {
    id: props.lead.id,
    custom_attributes: {
      ...(props.lead.custom_attributes || {}),
      colheita_status: next,
    },
  });
};

// extração da reunião feita pela IA (Ramon::ColheitaExtractionService)
const colheitaIA = computed(
  () => props.lead?.custom_attributes?.colheita || null
);
const lacunas = computed(() => colheitaIA.value?.lacunas || []);
const extractedAt = computed(() => {
  const iso = colheitaIA.value?.extraida_em;
  if (!iso) return '';
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleString('pt-BR');
});
</script>

<template>
  <div
    v-if="lead?.thesis_id && colheitaItems.length"
    class="flex flex-col gap-2"
    data-testid="colheita-checklist"
  >
    <div class="flex items-center justify-between">
      <span class="text-xs uppercase text-n-slate-10">{{
        $t('RAMON.COLHEITA.TITLE')
      }}</span>
      <span class="text-xs text-n-slate-10" data-testid="colheita-count">{{
        $t('RAMON.COLHEITA.COUNT', {
          done: doneCount,
          total: colheitaItems.length,
        })
      }}</span>
    </div>

    <button
      v-for="item in colheitaItems"
      :key="item.id"
      type="button"
      data-testid="colheita-item"
      class="flex items-start gap-2 px-3 py-2 text-sm text-left rounded-lg border transition-colors"
      :class="
        isDone(item)
          ? 'bg-n-teal-3 text-n-teal-11 border-n-teal-6'
          : 'bg-n-amber-3 text-n-amber-11 border-n-amber-6'
      "
      :title="item.content"
      @click="toggle(item)"
    >
      <span class="shrink-0 mt-0.5 text-xs">{{
        isDone(item) ? '✓' : '○'
      }}</span>
      <span :class="isDone(item) ? 'line-through opacity-70' : ''">{{
        item.title
      }}</span>
    </button>

    <div
      v-if="lacunas.length"
      class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="colheita-lacunas"
    >
      <span class="text-xs uppercase text-n-slate-10">{{
        $t('RAMON.COLHEITA.LACUNAS_TITLE')
      }}</span>
      <ul class="flex flex-col gap-1 text-sm text-n-slate-12">
        <li v-for="(lacuna, i) in lacunas" :key="i">
          <span class="font-medium">{{ lacuna.campo }}</span>
          <span v-if="lacuna.como_obter" class="text-n-slate-10">
            — {{ lacuna.como_obter }}</span
          >
        </li>
      </ul>
      <span v-if="extractedAt" class="text-xs text-n-slate-10">{{
        $t('RAMON.COLHEITA.EXTRACTED_AT', { date: extractedAt })
      }}</span>
    </div>
  </div>
</template>
