<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  lead: { type: Object, required: true },
  context: { type: String, default: 'drawer' },
});
defineOptions({ name: 'QualificacaoViva' });

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
  if (!current || !current.items) await store.dispatch('theses/show', thesisId);
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

const criterios = computed(() =>
  (thesis.value?.items || []).filter(item => item.section === 'qualificacao')
);
const statusMap = computed(
  () => props.lead?.custom_attributes?.qualificacao_status || {}
);
const statusOf = item => statusMap.value[item.id] || null;
const okCount = computed(
  () => criterios.value.filter(item => statusOf(item) === 'ok').length
);

// ciclo: null → ok → falta → null (backend faz deep_merge — só a chave vai)
const pendingIds = ref(new Set());
const cycle = async item => {
  if (pendingIds.value.has(item.id)) return;
  pendingIds.value.add(item.id);
  const next = { null: 'ok', ok: 'falta', falta: null }[String(statusOf(item))];
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      custom_attributes: { qualificacao_status: { [item.id]: next } },
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    pendingIds.value.delete(item.id);
  }
};

// "perguntar →": na conversa cai como rascunho no editor; na gaveta (sem
// ReplyBox montado) o caminho é o clipboard — mesmo fallback do DocChecklist.
const perguntar = async item => {
  if (props.context === 'conversation') {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, item.title);
    useAlert(t('RAMON.QUALIFICACAO.PERGUNTA_INSERIDA'));
  } else {
    try {
      await copyTextToClipboard(item.title);
    } catch (error) {
      useAlert(t('RAMON.DOCS.COPY_FAILED'));
      return;
    }
    useAlert(t('RAMON.DOCS.COPIED'));
  }
};
</script>

<template>
  <div
    v-if="lead?.thesis_id && criterios.length"
    class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-3"
    data-testid="panel-card-qualificacao"
  >
    <div class="flex items-center justify-between">
      <p
        class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10"
      >
        {{ $t('RAMON.QUALIFICACAO.TITLE') }}
      </p>
      <span
        class="text-xs font-semibold text-n-slate-12"
        data-testid="qualificacao-count"
      >
        {{
          $t('RAMON.QUALIFICACAO.COUNT', {
            ok: okCount,
            total: criterios.length,
          })
        }}
      </span>
    </div>
    <div class="mt-1.5 flex flex-col">
      <div
        v-for="item in criterios"
        :key="item.id"
        class="flex items-center gap-2 py-1.5 text-[12.5px]"
        data-testid="qualificacao-criterio"
      >
        <button
          type="button"
          data-testid="qualificacao-toggle"
          class="grid size-4.5 shrink-0 place-items-center rounded-full text-[10px]"
          :class="
            statusOf(item) === 'ok'
              ? 'bg-n-teal-3 text-n-teal-11'
              : statusOf(item) === 'falta'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-alpha-2 text-n-slate-10'
          "
          :disabled="pendingIds.has(item.id)"
          :title="$t('RAMON.QUALIFICACAO.CYCLE_HINT')"
          @click="cycle(item)"
        >
          {{
            statusOf(item) === 'ok'
              ? '✓'
              : statusOf(item) === 'falta'
                ? '!'
                : '·'
          }}
        </button>
        <span
          class="min-w-0 truncate"
          :class="
            statusOf(item) === 'ok' ? 'text-n-slate-12' : 'text-n-slate-11'
          "
        >
          {{ item.title }}
        </span>
        <button
          v-if="statusOf(item) !== 'ok'"
          type="button"
          data-testid="qualificacao-perguntar"
          class="ml-auto shrink-0 text-[11px] font-bold text-n-iris-11"
          @click="perguntar(item)"
        >
          {{ $t('RAMON.QUALIFICACAO.PERGUNTAR') }}
        </button>
      </div>
    </div>
  </div>
</template>
