<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'DocChecklist' });

const { t } = useI18n();
const store = useStore();
const theses = useMapGetter('theses/getTheses');

// ordem do ciclo de status de um documento
const CYCLE = ['pendente', 'solicitado', 'recebido'];

const thesis = computed(() =>
  theses.value.find(x => x.id === props.lead?.thesis_id)
);

// garante que os itens da tese estejam carregados (mesmo padrão do LeadPlaybook)
const ensureItems = async () => {
  const thesisId = props.lead?.thesis_id;
  if (!thesisId) return;
  const current = theses.value.find(x => x.id === thesisId);
  if (!current || !current.items) {
    await store.dispatch('theses/show', thesisId);
  }
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

const docItems = computed(() =>
  (thesis.value?.items || []).filter(item => item.section === 'documento')
);

// mapa { "<item_id>": status } vindo de custom_attributes.doc_status
const docStatus = computed(
  () => props.lead?.custom_attributes?.doc_status || {}
);

const statusOf = item => docStatus.value[item.id] || 'pendente';

const receivedCount = computed(
  () => docItems.value.filter(item => statusOf(item) === 'recebido').length
);

const hasChargeable = computed(() =>
  docItems.value.some(item => statusOf(item) !== 'recebido')
);

const itemLabel = item => item.title || item.content || '';

// grava o doc_status novo mesclando com o custom_attributes existente,
// sem sobrescrever nenhuma outra chave.
const persist = docStatusNext => {
  store.dispatch('leads/update', {
    id: props.lead.id,
    custom_attributes: {
      ...(props.lead.custom_attributes || {}),
      doc_status: docStatusNext,
    },
  });
};

const cycle = item => {
  const currentIndex = CYCLE.indexOf(statusOf(item));
  const next = CYCLE[(currentIndex + 1) % CYCLE.length];
  persist({ ...docStatus.value, [item.id]: next });
};

const chipClass = item => {
  const status = statusOf(item);
  if (status === 'recebido') {
    return 'bg-n-teal-3 text-n-teal-11 border-n-teal-6';
  }
  if (status === 'solicitado') {
    return 'bg-n-iris-3 text-n-iris-11 border-n-iris-6';
  }
  return 'bg-n-amber-3 text-n-amber-11 border-n-amber-6';
};

// "Cobrar pendentes": monta o rascunho, copia, avisa e marca os pendentes
// como solicitados. Nada é enviado automaticamente.
const chargePending = async () => {
  const pending = docItems.value.filter(item => statusOf(item) !== 'recebido');
  if (!pending.length) return;

  const lines = [
    t('RAMON.DOCS.DRAFT.GREETING', { name: props.lead?.name || '' }),
    '',
    ...pending.map(item =>
      t('RAMON.DOCS.DRAFT.ITEM', { item: itemLabel(item) })
    ),
    '',
    t('RAMON.DOCS.DRAFT.CLOSING'),
  ];
  try {
    await copyTextToClipboard(lines.join('\n'));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.DOCS.COPIED'));

  // marca só os que estavam pendentes como solicitados (merge)
  const next = { ...docStatus.value };
  pending.forEach(item => {
    if (statusOf(item) === 'pendente') next[item.id] = 'solicitado';
  });
  persist(next);
};
</script>

<template>
  <div
    v-if="lead?.thesis_id && docItems.length"
    class="flex flex-col gap-2 mb-4 pt-3 border-t border-n-weak"
    data-testid="doc-checklist"
  >
    <div class="flex items-center justify-between">
      <span class="text-xs uppercase text-n-slate-10">{{
        $t('RAMON.DOCS.TITLE')
      }}</span>
      <span class="text-xs text-n-slate-10" data-testid="doc-count">{{
        $t('RAMON.DOCS.COUNT', {
          received: receivedCount,
          total: docItems.length,
        })
      }}</span>
    </div>

    <button
      v-for="item in docItems"
      :key="item.id"
      type="button"
      data-testid="doc-chip"
      class="flex items-center justify-between gap-2 px-3 py-2 text-sm text-left rounded-lg border transition-colors"
      :class="chipClass(item)"
      :title="$t('RAMON.DOCS.CYCLE_HINT')"
      @click="cycle(item)"
    >
      <span class="truncate">{{ itemLabel(item) }}</span>
      <span class="shrink-0 text-xs uppercase tracking-wide">{{
        $t(`RAMON.DOCS.STATUS.${statusOf(item).toUpperCase()}`)
      }}</span>
    </button>

    <button
      type="button"
      data-testid="doc-charge"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!hasChargeable"
      @click="chargePending"
    >
      {{ $t('RAMON.DOCS.CHARGE') }}
    </button>
  </div>
</template>
