<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { SECAO, TITULO, CHIP, TOM, AVISO, LINHA } from '../../helpers/ui';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'ColheitaChecklist' });

const { t } = useI18n();
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

// mapa vindo de custom_attributes.colheita_status:
// true = marcado à mão · 'ia' = marcado pela IA · false = desmarcado à mão
// (veto explícito — a IA nunca re-marca chave existente)
const colheitaStatus = computed(
  () => props.lead?.custom_attributes?.colheita_status || {}
);

const isDone = item => Boolean(colheitaStatus.value[item.id]);
const isAI = item => colheitaStatus.value[item.id] === 'ia';

const doneCount = computed(() => colheitaItems.value.filter(isDone).length);

// grava o colheita_status novo mesclando com o custom_attributes existente,
// sem sobrescrever nenhuma outra chave. Guard por item: dois cliques rápidos
// no mesmo item invertiam o estado desejado.
const pendingIds = ref(new Set());
const toggle = async item => {
  if (pendingIds.value.has(item.id)) return;
  pendingIds.value.add(item.id);
  const next = { ...colheitaStatus.value, [item.id]: !isDone(item) };
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      custom_attributes: {
        ...(props.lead.custom_attributes || {}),
        colheita_status: next,
      },
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    pendingIds.value.delete(item.id);
  }
};

// extração sob demanda (decisão 20/07): o botão dispara o job; o resultado
// chega pelo broadcast do lead (custom_attributes.colheita) em alguns segundos.
const extracting = ref(false);
const extractColheita = async () => {
  if (extracting.value) return;
  extracting.value = true;
  try {
    await LeadsAPI.extractColheita(props.lead.id);
    useAlert(t('RAMON.COLHEITA.EXTRACT_REQUESTED'));
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    extracting.value = false;
  }
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
  // mesma máscara do fmtDateTime dos irmãos (sem segundos)
  return Number.isNaN(date.getTime())
    ? ''
    : date.toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      });
});

// artefato 3 da colheita: cada lacuna vira pedido de documento RASCUNHO —
// copia pro clipboard; quem revisa e envia é o humano, nada sai sozinho.
const chargeLacunas = async () => {
  if (!lacunas.value.length) return;
  const lines = [
    t('RAMON.COLHEITA.DRAFT.GREETING', { name: props.lead?.name || '' }),
    '',
    ...lacunas.value.map(lacuna =>
      t('RAMON.COLHEITA.DRAFT.ITEM', {
        item: lacuna.como_obter || lacuna.campo,
      })
    ),
    '',
    t('RAMON.COLHEITA.DRAFT.CLOSING'),
  ];
  try {
    await copyTextToClipboard(lines.join('\n'));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.COLHEITA.COPIED'));
};
</script>

<template>
  <div
    v-if="lead?.thesis_id && colheitaItems.length"
    class="flex flex-col gap-2 mb-4"
    :class="SECAO"
    data-testid="colheita-checklist"
  >
    <div class="flex items-center justify-between">
      <span :class="TITULO">{{ $t('RAMON.COLHEITA.TITLE') }}</span>
      <span
        class="font-mono text-xs text-n-slate-10"
        data-testid="colheita-count"
        >{{
          $t('RAMON.COLHEITA.COUNT', {
            done: doneCount,
            total: colheitaItems.length,
          })
        }}</span
      >
    </div>

    <button
      v-for="item in colheitaItems"
      :key="item.id"
      type="button"
      data-testid="colheita-item"
      class="flex items-center justify-between gap-2"
      :class="LINHA"
      :title="item.content"
      :aria-pressed="isDone(item)"
      :disabled="pendingIds.has(item.id)"
      @click="toggle(item)"
    >
      <span
        class="truncate"
        :class="
          isDone(item) ? 'text-n-slate-10 line-through' : 'text-n-slate-12'
        "
        >{{ item.title || item.content }}</span
      >
      <span
        v-if="isAI(item)"
        class="shrink-0"
        :class="[CHIP, TOM.iris]"
        data-testid="colheita-ai-badge"
        :title="$t('RAMON.COLHEITA.AI_BADGE_TIP')"
        >{{ $t('RAMON.COLHEITA.AI_BADGE') }}</span
      >
      <span
        v-else
        class="shrink-0"
        :class="[CHIP, isDone(item) ? TOM.teal : TOM.amber]"
      >
        <span
          class="size-3"
          :class="isDone(item) ? 'i-lucide-check' : 'i-lucide-circle'"
        />
      </span>
    </button>

    <div
      v-if="lacunas.length"
      class="flex flex-col gap-1"
      :class="[AVISO, TOM.amber]"
      data-testid="colheita-lacunas"
    >
      <span :class="TITULO">{{ $t('RAMON.COLHEITA.LACUNAS_TITLE') }}</span>
      <ul class="flex flex-col gap-1 text-sm text-n-slate-12 list-none ps-0">
        <li v-for="(lacuna, i) in lacunas" :key="i">
          <span class="font-medium">{{ lacuna.campo }}</span>
          <span v-if="lacuna.como_obter" class="text-n-slate-11">
            — {{ lacuna.como_obter }}</span
          >
        </li>
      </ul>
      <span v-if="extractedAt" class="text-xs text-n-slate-10">{{
        $t('RAMON.COLHEITA.EXTRACTED_AT', { date: extractedAt })
      }}</span>
    </div>

    <div class="flex flex-wrap gap-2">
      <Button
        data-testid="colheita-extract"
        sm
        faded
        slate
        icon="i-lucide-sparkles"
        :label="$t('RAMON.COLHEITA.EXTRACT')"
        :is-loading="extracting"
        :disabled="extracting"
        @click="extractColheita"
      />
      <Button
        v-if="lacunas.length"
        data-testid="colheita-charge"
        sm
        faded
        slate
        :label="$t('RAMON.COLHEITA.CHARGE')"
        @click="chargeLacunas"
      />
    </div>
  </div>
</template>
