<script setup>
import { ref, computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  lead: { type: Object, default: null },
});
defineOptions({ name: 'LeadPlaybook' });

const store = useStore();
const theses = useMapGetter('theses/getTheses');

// só estas 3 seções aparecem no painel de consulta durante a conversa
const SECTIONS = ['qualificacao', 'objecao', 'documento'];

const thesis = computed(() =>
  theses.value.find(t => t.id === props.lead?.thesis_id)
);

const ensureItems = async () => {
  const thesisId = props.lead?.thesis_id;
  if (!thesisId) return;
  const current = theses.value.find(t => t.id === thesisId);
  if (!current || !current.items) {
    await store.dispatch('theses/show', thesisId);
  }
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

const sections = computed(() => {
  const items = thesis.value?.items || [];
  return SECTIONS.map(section => ({
    section,
    items: items.filter(item => item.section === section),
  })).filter(group => group.items.length);
});

const copiedId = ref(null);
const copy = async item => {
  try {
    await navigator.clipboard.writeText(item.content);
    copiedId.value = item.id;
    setTimeout(() => {
      if (copiedId.value === item.id) copiedId.value = null;
    }, 1500);
  } catch (e) {
    // navegador sem permissão/API de clipboard: falha silenciosa, sem quebrar a UI
  }
};

const sectionLabelKey = section =>
  `RAMON.PLAYBOOK.SECTIONS.${section.toUpperCase()}`;
</script>

<template>
  <div class="flex flex-col gap-4 p-1" data-testid="lead-playbook">
    <p
      v-if="!lead?.thesis_id"
      class="text-sm text-n-slate-10"
      data-testid="playbook-empty"
    >
      {{ $t('RAMON.PLAYBOOK.EMPTY') }}
    </p>
    <template v-else>
      <div
        v-for="group in sections"
        :key="group.section"
        class="flex flex-col gap-2"
        data-testid="playbook-section"
      >
        <span class="text-xs uppercase tracking-widest text-n-slate-9">
          {{ $t(sectionLabelKey(group.section)) }}
        </span>
        <div
          v-for="item in group.items"
          :key="item.id"
          data-testid="playbook-item"
          class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
        >
          <div class="flex items-start justify-between gap-2">
            <strong v-if="item.title" class="text-sm text-n-slate-12">{{
              item.title
            }}</strong>
            <button
              class="shrink-0 px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
              data-testid="playbook-copy"
              @click="copy(item)"
            >
              {{
                copiedId === item.id
                  ? $t('RAMON.PLAYBOOK.COPIED')
                  : $t('RAMON.PLAYBOOK.COPY')
              }}
            </button>
          </div>
          <p class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ item.content }}
          </p>
        </div>
      </div>
    </template>
  </div>
</template>
