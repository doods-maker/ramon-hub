<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadsAPI from 'dashboard/api/leads';
import { CARTAO, TITULO } from '../../helpers/ui';
import RoteiroDoLead from './RoteiroDoLead.vue';

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
// Roteiro da IA (F2): com passos na tese, o card mostra o roteiro passo a passo no lugar do checklist (tese só com
// os passos comuns mostra os dois). Recarrega quando o broadcast do lead traz outra roteiro_versao — a chave em
// texto evita recarregar a cada broadcast que não mexeu no roteiro.
const roteiro = ref(null);
let pedido = 0;
// painel reaberto: invalida carga em voo, que sobrescreveria o estado novo
const reaberto = novo => {
  pedido += 1;
  roteiro.value = novo;
};
const carregarRoteiro = async () => {
  pedido += 1;
  const meu = pedido;
  if (!props.lead?.id) {
    roteiro.value = null;
    return;
  }
  try {
    const { data } = await LeadsAPI.roteiro(props.lead.id);
    if (meu === pedido) roteiro.value = data?.passos ? data : null;
  } catch {
    if (meu === pedido) roteiro.value = null;
  }
};
watch(
  () =>
    `${props.lead?.id}|${props.lead?.thesis_id}|${props.lead?.roteiro_versao}`,
  carregarRoteiro,
  { immediate: true }
);
const bloqueio = computed(() => {
  if (props.lead?.won_at) return 'ganho';
  return props.lead?.lost_at ? 'perdido' : '';
});

const statusMap = computed(
  () => props.lead?.custom_attributes?.qualificacao_status || {}
);
const statusOf = item => statusMap.value[item.id] || null;
// ícone + cor do botão de status (ok → falta → sem marca)
const STATUS_UI = {
  ok: { icon: 'i-lucide-check', color: 'teal' },
  falta: { icon: 'i-lucide-circle-alert', color: 'amber' },
  null: { icon: 'i-lucide-circle-dashed', color: 'slate' },
};
const statusUi = item => STATUS_UI[String(statusOf(item))] || STATUS_UI.null;
const okCount = computed(
  () => criterios.value.filter(item => statusOf(item) === 'ok').length
);
const todasOk = computed(() => okCount.value === criterios.value.length);
// pendentes sempre à vista; respondidas só com o toggle aberto
const respondidasAbertas = ref(false);
const visiveis = computed(() =>
  respondidasAbertas.value
    ? criterios.value
    : criterios.value.filter(item => statusOf(item) !== 'ok')
);

// ciclo: null → ok → falta → null (backend faz deep_merge — só a chave vai)
const pendingIds = ref(new Set());
const cycle = async item => {
  if (pendingIds.value.has(item.id)) return;
  pendingIds.value.add(item.id);
  const next =
    { null: 'ok', ok: 'falta', falta: null }[String(statusOf(item))] ?? 'ok';
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
  <!-- compacto: só as pendentes à vista; respondidas recolhidas atrás de um
       toggle (order-* põe o toggle entre as duas listas num v-for só) -->
  <RoteiroDoLead
    v-if="roteiro"
    :roteiro="roteiro"
    :lead-id="lead.id"
    :bloqueio="bloqueio"
    @reaberto="reaberto"
  />
  <div
    v-if="
      lead?.thesis_id && criterios.length && (!roteiro || roteiro.so_comuns)
    "
    :class="CARTAO"
    data-testid="panel-card-qualificacao"
  >
    <button
      v-if="todasOk"
      type="button"
      data-testid="qualificacao-ok"
      class="flex items-center w-full gap-1.5 p-0 text-left text-xs font-semibold text-n-teal-11"
      @click="respondidasAbertas = !respondidasAbertas"
    >
      <span class="i-lucide-check size-3.5 shrink-0" />
      {{
        $t('RAMON.QUALIFICACAO.QUALIFICADO', {
          ok: okCount,
          total: criterios.length,
        })
      }}
      <span
        class="ml-auto size-3.5 shrink-0"
        :class="
          respondidasAbertas
            ? 'i-lucide-chevron-down'
            : 'i-lucide-chevron-right'
        "
      />
    </button>
    <div v-else class="flex items-center gap-2">
      <p :class="TITULO">
        {{ $t('RAMON.QUALIFICACAO.TITLE') }}
      </p>
      <div class="flex-1 h-1 overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full bg-n-teal-9"
          :style="{ width: `${(okCount / criterios.length) * 100}%` }"
        />
      </div>
      <span
        class="font-mono text-xs font-semibold text-n-slate-12"
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
    <div class="mt-1 flex flex-col">
      <div
        v-for="item in visiveis"
        :key="item.id"
        class="flex items-center gap-2 py-1 text-[12.5px]"
        :class="statusOf(item) === 'ok' ? 'order-3' : 'order-1'"
        data-testid="qualificacao-criterio"
      >
        <Button
          data-testid="qualificacao-toggle"
          xs
          faded
          class="shrink-0"
          :color="statusUi(item).color"
          :icon="statusUi(item).icon"
          :disabled="pendingIds.has(item.id)"
          :title="$t('RAMON.QUALIFICACAO.CYCLE_HINT')"
          @click="cycle(item)"
        />
        <span
          class="min-w-0 truncate"
          :class="
            statusOf(item) === 'ok' ? 'text-n-slate-12' : 'text-n-slate-11'
          "
        >
          {{ item.title }}
        </span>
        <Button
          v-if="statusOf(item) !== 'ok'"
          data-testid="qualificacao-perguntar"
          link
          xs
          class="ml-auto shrink-0"
          :label="$t('RAMON.QUALIFICACAO.PERGUNTAR')"
          @click="perguntar(item)"
        />
      </div>
      <Button
        v-if="okCount && !todasOk"
        data-testid="qualificacao-respondidas"
        link
        slate
        xs
        trailing-icon
        class="order-2 self-start mt-1"
        :icon="
          respondidasAbertas
            ? 'i-lucide-chevron-down'
            : 'i-lucide-chevron-right'
        "
        :label="$t('RAMON.QUALIFICACAO.RESPONDIDAS', { count: okCount })"
        @click="respondidasAbertas = !respondidasAbertas"
      />
    </div>
  </div>
</template>
