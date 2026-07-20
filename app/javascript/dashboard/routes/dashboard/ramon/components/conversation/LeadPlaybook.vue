<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  lead: { type: Object, default: null },
});
defineOptions({ name: 'LeadPlaybook' });

const { t } = useI18n();
const store = useStore();
const theses = useMapGetter('theses/getTheses');
const stages = useMapGetter('leadConfig/getStages');

// seções que aparecem no painel de consulta durante a conversa
const SECTIONS = ['qualificacao', 'apresentacao', 'objecao', 'documento'];

// mapa estático etapa (nome seedado) → seção destacada "nesta etapa".
// Etapa custom sem match cai no comportamento padrão (nenhum destaque).
const STAGE_SECTION = {
  Novo: 'qualificacao',
  Qualificação: 'qualificacao',
  'Reunião agendada': 'apresentacao',
  'Reunião realizada': 'apresentacao',
  Negociação: 'objecao',
  'Última chance': 'objecao',
  Fechado: 'documento',
};

const thesis = computed(() =>
  theses.value.find(x => x.id === props.lead?.thesis_id)
);

const currentStageName = computed(
  () => (stages.value || []).find(s => s.id === props.lead?.lead_stage_id)?.name
);

const highlightedSection = computed(
  () => STAGE_SECTION[currentStageName.value] || null
);

const loadFailed = ref(false);
const ensureItems = async () => {
  const thesisId = props.lead?.thesis_id;
  if (!thesisId) return;
  loadFailed.value = false;
  const current = theses.value.find(x => x.id === thesisId);
  if (!current || !current.items) {
    try {
      await store.dispatch('theses/show', thesisId);
    } catch (e) {
      loadFailed.value = true;
    }
  }
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

// itens ainda não carregados (undefined) e sem falha = carregando
const itemsLoading = computed(
  () => !Array.isArray(thesis.value?.items) && !loadFailed.value
);

const sections = computed(() => {
  const items = thesis.value?.items || [];
  const groups = SECTIONS.map(section => ({
    section,
    items: items.filter(item => item.section === section),
    highlighted: section === highlightedSection.value,
  })).filter(group => group.items.length);
  // a seção da etapa atual vai para o topo, expandida com o selo "nesta etapa"
  return [...groups].sort(
    (a, b) => Number(b.highlighted) - Number(a.highlighted)
  );
});

const copiedId = ref(null);
const copy = async item => {
  try {
    await copyTextToClipboard(item.content);
  } catch (e) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  copiedId.value = item.id;
  setTimeout(() => {
    if (copiedId.value === item.id) copiedId.value = null;
  }, 1500);
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
    <p
      v-else-if="itemsLoading"
      class="text-sm text-n-slate-10"
      data-testid="playbook-loading"
    >
      {{ $t('RAMON.PLAYBOOK.LOADING') }}
    </p>
    <p
      v-else-if="!sections.length"
      class="text-sm text-n-slate-10"
      data-testid="playbook-no-items"
    >
      {{ $t('RAMON.PLAYBOOK.NO_ITEMS') }}
    </p>
    <template v-else>
      <div
        v-for="group in sections"
        :key="group.section"
        class="flex flex-col gap-2"
        data-testid="playbook-section"
      >
        <span class="flex items-center gap-2">
          <span class="text-xs uppercase tracking-widest text-n-slate-9">
            {{ $t(sectionLabelKey(group.section)) }}
          </span>
          <span
            v-if="group.highlighted"
            data-testid="playbook-stage-badge"
            class="px-1.5 py-0.5 text-[10px] uppercase tracking-wide rounded bg-n-iris-3 text-n-iris-11 border border-n-iris-6"
          >
            {{ $t('RAMON.PLAYBOOK.THIS_STAGE') }}
          </span>
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
