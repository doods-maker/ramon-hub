<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { SECAO, TITULO, CHIP, TOM, AVISO, LINHA } from '../../helpers/ui';
import { colheitaCampos } from '../../helpers/colheitaCampos';
import { docChargeDraft } from '../../helpers/docCobranca';

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

// Extração sob demanda: o botão enfileira o job; o resultado chega pelo
// broadcast do lead (custom_attributes.colheita) em alguns segundos. O job lê a
// conversa do lead — sem conversa não há o que extrair, e o botão some.
const podeExtrair = computed(() => Boolean(props.lead?.conversation_id));
const extracting = ref(false);
const extractColheita = async () => {
  if (extracting.value) return;
  extracting.value = true;
  try {
    await LeadsAPI.extractColheita(props.lead.id);
    useAlert(t('RAMON.COLHEITA.EXTRACT_REQUESTED'));
  } catch (e) {
    useAlert(t('RAMON.COLHEITA.EXTRACT_FAILED'));
  } finally {
    extracting.value = false;
  }
};

// Resultado da IA (Ramon::ColheitaExtractionService): dados, lacunas, confirmar.
const colheitaIA = computed(
  () => props.lead?.custom_attributes?.colheita || null
);
const dadosColhidos = computed(() =>
  colheitaCampos(colheitaIA.value?.dados, colheitaIA.value?.confirmar)
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

// Cada lacuna vira pedido de documento em RASCUNHO, copiado para a área de
// transferência; quem revisa e envia é uma pessoa, nada sai sozinho.
const chargeLacunas = async () => {
  if (!lacunas.value.length) return;
  const draft = docChargeDraft(
    t,
    props.lead?.name,
    lacunas.value.map(lacuna => lacuna.como_obter || lacuna.campo),
    'RAMON.COLHEITA.DRAFT'
  );
  try {
    await copyTextToClipboard(draft);
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.COLHEITA.COPIED'));
};
</script>

<template>
  <div
    v-if="lead?.thesis_id"
    class="flex flex-col gap-2 mb-4"
    :class="SECAO"
    data-testid="colheita-checklist"
  >
    <div v-if="colheitaItems.length" class="flex items-center justify-between">
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
      v-if="dadosColhidos.length"
      class="flex flex-col gap-1.5 pt-1"
      data-testid="colheita-dados"
    >
      <span :class="TITULO">{{ $t('RAMON.COLHEITA.DADOS_TITLE') }}</span>
      <dl class="flex flex-col gap-1.5 text-sm">
        <div
          v-for="(dado, i) in dadosColhidos"
          :key="i"
          class="flex items-baseline justify-between gap-3"
          data-testid="colheita-dado"
        >
          <dt class="shrink-0 text-n-slate-10">
            {{ $t(`RAMON.COLHEITA.CAMPO.${dado.chave}`) }}
          </dt>
          <dd class="flex items-baseline gap-1.5 text-right text-n-slate-12">
            <span>{{ dado.valor }}</span>
            <span
              v-if="dado.confirmar"
              class="shrink-0"
              :class="[CHIP, TOM.amber]"
              :title="$t('RAMON.COLHEITA.CONFIRMAR_TIP')"
              >{{ $t('RAMON.COLHEITA.CONFIRMAR') }}</span
            >
          </dd>
        </div>
      </dl>
    </div>

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
        v-if="podeExtrair"
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
