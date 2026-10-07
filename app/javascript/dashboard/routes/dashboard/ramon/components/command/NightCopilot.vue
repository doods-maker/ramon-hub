<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, CHIP, SECAO, TOM } from '../../helpers/ui';

// I-WD2: a Visão geral abre o Centro com ?sugestoes=todas|<tipo> — o bloco já
// vem aberto (sem gravar a preferência), rolado até aqui e, com tipo, filtrado.
const props = defineProps({ foco: { type: String, default: '' } });

// "Enquanto você dormia" (mock 4b): sugestões do copiloto noturno no topo do
// Cockpit. Nada é enviado ao cliente — aplicar rascunho vira NOTA no lead.
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const suggestions = computed(
  () => getters['copilotSuggestions/getSuggestions'].value
);
const meta = computed(() => getters['copilotSuggestions/getMeta'].value);
const uiFlags = computed(() => getters['copilotSuggestions/getUIFlags'].value);

onMounted(() => store.dispatch('copilotSuggestions/fetch'));

// Recolhido por padrão (uma linha); aberto/fechado fica lembrado no navegador.
const EXPANDED_KEY = 'ramon_night_copilot_expanded';
const readExpanded = () => {
  try {
    return localStorage.getItem(EXPANDED_KEY) === '1';
  } catch (e) {
    return false;
  }
};
const expanded = ref(props.foco ? true : readExpanded());
const toggleExpanded = () => {
  expanded.value = !expanded.value;
  try {
    localStorage.setItem(EXPANDED_KEY, expanded.value ? '1' : '0');
  } catch (e) {
    // localStorage indisponível: vale só nesta visita
  }
};

// "Aprovar todas" cobre só draft/alert — move_stage e acao são cartão a
// cartão, porque tocam funil e sistema externo (ZapSign/AdvBox/Esteira).
const bulkCount = computed(
  () =>
    suggestions.value.filter(s => s.kind === 'draft' || s.kind === 'alert')
      .length
);

// Tipo = a ação em sistema ou o kind (igual ao contador da Visão geral).
const tipoDe = s => s.payload?.acao || s.kind;
const tipoFiltro = ref(props.foco && props.foco !== 'todas' ? props.foco : '');
const visiveis = computed(() =>
  tipoFiltro.value
    ? suggestions.value.filter(s => tipoDe(s) === tipoFiltro.value)
    : suggestions.value
);
const rotuloTipo = computed(() =>
  t(`CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO.${tipoFiltro.value}`)
);

// Rola até o bloco quando as sugestões chegam (o bloco só existe com > 0).
const raiz = ref(null);
let rolou = false;
watch(
  () => suggestions.value.length,
  total => {
    if (!total || !props.foco || rolou) return;
    rolou = true;
    nextTick(() =>
      raiz.value?.scrollIntoView?.({ behavior: 'smooth', block: 'start' })
    );
  },
  { immediate: true }
);

const runTime = computed(() => {
  const withRun = suggestions.value.find(s => s.run_at);
  if (!withRun) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(withRun.run_at));
});

const TAGS = {
  draft: {
    label: 'RAMON.NIGHT_COPILOT.TAG_DRAFT',
    class: TOM.blue,
  },
  move_stage: {
    label: 'RAMON.NIGHT_COPILOT.TAG_MOVE_STAGE',
    class: TOM.amber,
  },
  alert: {
    label: 'RAMON.NIGHT_COPILOT.TAG_ALERT',
    class: TOM.ruby,
  },
  acao: {
    label: 'RAMON.NIGHT_COPILOT.TAG_ACAO',
    class: TOM.teal,
  },
};
const tagFor = kind => TAGS[kind] || TAGS.alert;

const bodyText = s => {
  if (s.kind === 'draft') return `"${s.payload.texto || ''}"`;
  if (s.kind === 'acao') return s.payload.texto || '';
  return s.payload.justificativa || '';
};

// Guard de duplo-clique por cartão.
const actingId = ref(null);
const isBulkActing = ref(false);

const apply = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('copilotSuggestions/apply', suggestion.id);
    useAlert(t('RAMON.NIGHT_COPILOT.APPLIED'));
  } catch (e) {
    // o motivo real (ZapSign fora do ar, caso não ganho) vem do servidor
    useAlert(e?.response?.data?.error || t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const dismiss = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('copilotSuggestions/dismiss', suggestion.id);
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

// Alerta → tarefa follow_up pra hoje (Esteira) + marca como aplicada.
const escalate = async suggestion => {
  if (actingId.value) return;
  actingId.value = suggestion.id;
  try {
    await store.dispatch('leadTasks/create', {
      leadId: suggestion.lead_id,
      title: t('RAMON.NIGHT_COPILOT.ESCALATE_TASK_TITLE'),
      kind: 'follow_up',
      dueAt: new Date(new Date().setHours(23, 59, 0, 0)).toISOString(),
    });
    await store.dispatch('copilotSuggestions/apply', suggestion.id);
    useAlert(t('RAMON.NIGHT_COPILOT.ESCALATED'));
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const applyAll = async () => {
  if (isBulkActing.value) return;
  isBulkActing.value = true;
  try {
    await store.dispatch('copilotSuggestions/applyAll');
    useAlert(t('RAMON.NIGHT_COPILOT.APPLIED_ALL'));
  } catch (e) {
    useAlert(t('RAMON.NIGHT_COPILOT.APPLY_ERROR'));
  } finally {
    isBulkActing.value = false;
  }
};

const retry = () => store.dispatch('copilotSuggestions/fetch');
</script>

<template>
  <!-- Erro de carga: retry explícito em vez de sumir calado -->
  <div
    v-if="uiFlags.hasError"
    data-testid="night-copilot-error"
    :class="CARTAO"
    class="text-sm"
  >
    <p class="text-n-ruby-11">{{ t('RAMON.NIGHT_COPILOT.LOAD_ERROR') }}</p>
    <Button
      data-testid="night-copilot-retry"
      link
      xs
      class="mt-1"
      :label="t('RAMON.NIGHT_COPILOT.RETRY')"
      @click="retry"
    />
  </div>

  <!-- Bloco some quando não há sugestão pendente -->
  <section
    v-else-if="suggestions.length"
    ref="raiz"
    data-testid="night-copilot"
    :class="CARTAO"
    class="!p-4"
  >
    <div class="flex items-center gap-2.5" :class="{ 'mb-1': expanded }">
      <span
        class="flex items-center justify-center flex-none rounded-lg size-8"
        :class="TOM.blue"
      >
        <span class="i-lucide-bot size-4" />
      </span>
      <div class="min-w-0">
        <p class="text-sm font-semibold truncate text-n-slate-12">
          {{ t('RAMON.NIGHT_COPILOT.TITLE') }}
          <span
            v-if="!expanded"
            data-testid="night-copilot-pending"
            class="ml-1.5 text-xs font-normal text-n-slate-10"
          >
            {{
              t('RAMON.NIGHT_COPILOT.PENDING', { count: suggestions.length })
            }}
          </span>
        </p>
        <p v-if="expanded" class="text-[11px] text-n-slate-10 truncate">
          {{
            t('RAMON.NIGHT_COPILOT.SUBTITLE', {
              leads: meta.reviewedCount,
              time: runTime,
              count: suggestions.length,
            })
          }}
        </p>
      </div>
      <div class="flex items-center flex-none gap-1.5 ml-auto">
        <Button
          v-if="bulkCount && !tipoFiltro"
          data-testid="night-copilot-apply-all"
          sm
          :label="t('RAMON.NIGHT_COPILOT.APPROVE_ALL', { count: bulkCount })"
          :disabled="isBulkActing"
          @click="applyAll"
        />
        <Button
          data-testid="night-copilot-toggle"
          sm
          ghost
          slate
          :icon="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          :title="
            expanded
              ? t('RAMON.NIGHT_COPILOT.COLLAPSE')
              : t('RAMON.NIGHT_COPILOT.EXPAND')
          "
          :aria-expanded="expanded"
          @click="toggleExpanded"
        />
      </div>
    </div>

    <div v-if="expanded" class="flex flex-col gap-3">
      <div
        v-if="tipoFiltro"
        data-testid="night-copilot-filtro"
        class="flex items-center gap-2 mt-2"
      >
        <span :class="[CHIP, TOM.amber]">
          {{ t('INTEL.SUGESTOES.SO_TIPO', { tipo: rotuloTipo }) }}
        </span>
        <Button
          data-testid="night-copilot-ver-todas"
          link
          xs
          :label="t('INTEL.SUGESTOES.VER_TODAS')"
          @click="tipoFiltro = ''"
        />
      </div>
      <p v-if="tipoFiltro && !visiveis.length" class="text-xs text-n-slate-10">
        {{ t('INTEL.SUGESTOES.NENHUMA_DO_TIPO') }}
      </p>
      <div
        v-for="suggestion in visiveis"
        :key="suggestion.id"
        data-testid="night-copilot-card"
        :class="SECAO"
      >
        <div class="flex items-center gap-2">
          <span :class="[CHIP, tagFor(suggestion.kind).class]">
            {{ t(tagFor(suggestion.kind).label) }}
          </span>
          <p class="text-[13px] font-medium text-n-slate-12 truncate">
            {{ suggestion.lead_name }}
          </p>
          <span
            v-if="suggestion.payload.days_stalled"
            class="ml-auto text-[10.5px] text-n-slate-10 flex-none"
          >
            {{
              t('RAMON.NIGHT_COPILOT.STALLED_FOR', {
                days: suggestion.payload.days_stalled,
              })
            }}
          </span>
        </div>

        <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
          {{ bodyText(suggestion) }}
          <b
            v-if="suggestion.kind === 'move_stage'"
            class="font-semibold text-n-slate-12"
          >
            {{
              t('RAMON.NIGHT_COPILOT.MOVE_TO', {
                stage: suggestion.payload.etapa_sugerida,
              })
            }}
          </b>
        </p>

        <div class="flex gap-1.5 mt-2">
          <Button
            v-if="suggestion.kind === 'draft'"
            data-testid="night-copilot-apply"
            xs
            faded
            teal
            :label="t('RAMON.NIGHT_COPILOT.SAVE_NOTE')"
            :disabled="actingId === suggestion.id"
            @click="apply(suggestion)"
          />
          <Button
            v-else-if="
              suggestion.kind === 'move_stage' || suggestion.kind === 'acao'
            "
            data-testid="night-copilot-apply"
            xs
            faded
            teal
            :label="t('RAMON.NIGHT_COPILOT.APPLY')"
            :disabled="actingId === suggestion.id"
            @click="apply(suggestion)"
          />
          <template v-else>
            <Button
              data-testid="night-copilot-apply"
              xs
              faded
              slate
              :label="t('RAMON.NIGHT_COPILOT.OK')"
              :disabled="actingId === suggestion.id"
              @click="apply(suggestion)"
            />
            <Button
              data-testid="night-copilot-escalate"
              xs
              :label="t('RAMON.NIGHT_COPILOT.ESCALATE')"
              :disabled="actingId === suggestion.id"
              @click="escalate(suggestion)"
            />
          </template>
          <Button
            v-if="suggestion.kind !== 'alert'"
            data-testid="night-copilot-dismiss"
            xs
            ghost
            slate
            :label="t('RAMON.NIGHT_COPILOT.DISMISS')"
            :disabled="actingId === suggestion.id"
            @click="dismiss(suggestion)"
          />
        </div>
      </div>
    </div>
  </section>
</template>
