<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { dynamicTime } from 'shared/helpers/timeHelper';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// Estado local simples: o item atual é sempre items[0].
// Pular gira a fila; Feito/Adiar removem o item.
const items = ref([]);
const doneCount = ref(0);
const isLoading = ref(true);
const hasError = ref(false);

const fetchEsteira = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await RamonEsteiraAPI.get();
    items.value = data.items || [];
    doneCount.value = data.board?.done_today || 0;
  } catch (e) {
    // Erro de API não pode virar "esteira zerada" comemorativa.
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};
onMounted(fetchEsteira);

const brl = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(Number(value) || 0);

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0);

const total = computed(() => items.value.length);
const valueSum = computed(() =>
  items.value.reduce((sum, item) => sum + (Number(item.value) || 0), 0)
);
const current = computed(() => items.value[0] || null);
const upcoming = computed(() => items.value.slice(1));
const nextThree = computed(() => upcoming.value.slice(0, 3));

// Progresso do dia: feitas / (feitas + na fila) — a barra bronze do topo.
const dayTotal = computed(() => doneCount.value + total.value);
const progressPct = computed(() =>
  dayTotal.value ? Math.round((doneCount.value / dayTotal.value) * 100) : 0
);

// Motivo legível: chaves i18n vindas do backend; moeda formatada aqui.
const reasonLabel = reason =>
  t(
    `RAMON.ESTEIRA.REASON.${reason.key}`,
    reason.key === 'PRESCRIPTION_BLEEDING'
      ? { value: brl(reason.params.monthly) }
      : reason.params
  );

// Chips de motivo com severidade (mock 1h): prescrição ruby sólido,
// tarefa âmbar, resto neutro.
const reasonChipClass = key => {
  if (key.startsWith('PRESCRIPTION')) return 'bg-n-ruby-9 text-white';
  if (key.startsWith('TASK')) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

// Dot de severidade do "Depois desta".
const severityDotClass = item => {
  const key = item.reasons[0]?.key || '';
  if (key.startsWith('PRESCRIPTION')) return 'bg-n-ruby-9';
  if (key === 'TASK_OVERDUE' || key === 'STALLED') return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};

// ---- Script do playbook (tese do lead atual) -----------------------------
const theses = useMapGetter('theses/getTheses');
const thesis = computed(() =>
  current.value?.thesis_id
    ? theses.value.find(x => x.id === current.value.thesis_id)
    : null
);

const ensureThesisItems = async () => {
  const thesisId = current.value?.thesis_id;
  if (!thesisId) return;
  const cached = theses.value.find(x => x.id === thesisId);
  if (cached?.items) return;
  try {
    await store.dispatch('theses/show', thesisId);
  } catch (e) {
    // sem tese carregada = bloco de script simplesmente não aparece
  }
};
watch(() => current.value?.thesis_id, ensureThesisItems, { immediate: true });

const sectionItems = section =>
  (thesis.value?.items || []).filter(i => i.section === section).slice(0, 2);
const scriptItems = computed(() => sectionItems('abertura'));
const objecaoItems = computed(() => sectionItems('objecao'));
const showScript = computed(
  () => scriptItems.value.length > 0 || objecaoItems.value.length > 0
);
const objecoesOpen = ref(false);

const copiedId = ref(null);
const copyScript = async item => {
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

// ---- Última mensagem / última simulação ----------------------------------
const lastMessage = computed(() => current.value?.last_message || null);
const lastMessageTime = computed(() =>
  lastMessage.value ? dynamicTime(lastMessage.value.at) : ''
);

const sim = computed(() => current.value?.ultima_simulacao || null);
const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');
const simParamsLine = computed(() => {
  if (!sim.value) return '';
  const parts = [];
  if (sim.value.mensal)
    parts.push(
      t('RAMON.ESTEIRA.LAST_SIMULATION_RMI', { value: money(sim.value.mensal) })
    );
  if (sim.value.parametros?.der)
    parts.push(
      t('RAMON.ESTEIRA.LAST_SIMULATION_DER', {
        value: dataBr(sim.value.parametros.der),
      })
    );
  if (sim.value.honorario_valor)
    parts.push(
      t('RAMON.ESTEIRA.LAST_SIMULATION_FEE', {
        value: money(sim.value.honorario_valor),
      })
    );
  return parts.join(' · ');
});
const simDate = computed(() =>
  sim.value?.em ? new Date(sim.value.em).toLocaleDateString() : ''
);

// ---- Ações ---------------------------------------------------------------
const skip = () => {
  if (items.value.length > 1) items.value.push(items.value.shift());
};

// Clique na lista dos próximos: traz o item pra frente da fila.
const jumpTo = index => {
  const [item] = items.value.splice(index + 1, 1);
  items.value.unshift(item);
};

// Guarda compartilhada: duplo-acionamento em Feito/Adiar comia o próximo.
const isActing = ref(false);

const markDone = async () => {
  const item = current.value;
  if (!item || isActing.value) return;
  isActing.value = true;
  try {
    await RamonEsteiraAPI.done(item.lead_id);
    doneCount.value += 1;
    items.value.shift();
    useAlert(t('RAMON.ESTEIRA.DONE_TOAST'));
  } catch (e) {
    useAlert(t('RAMON.ESTEIRA.ACTION_ERROR'));
  } finally {
    isActing.value = false;
  }
};

const snooze = async () => {
  const item = current.value;
  if (!item || isActing.value) return;
  isActing.value = true;
  try {
    await RamonEsteiraAPI.snooze(item.lead_id, item.task_id);
    items.value.shift();
    useAlert(t('RAMON.ESTEIRA.SNOOZED_TOAST'));
  } catch (e) {
    useAlert(t('RAMON.ESTEIRA.ACTION_ERROR'));
  } finally {
    isActing.value = false;
  }
};

// Abrir conversa (padrão do fork: funil + dock); sem conversa → Linha da Vida.
const openConversation = () => {
  const item = current.value;
  if (!item) return;
  if (item.conversation_id) {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/toggleDock', item.conversation_id);
  } else if (item.contact_id) {
    router.push(
      accountScopedRoute('ramon_linha_da_vida', { contactId: item.contact_id })
    );
  } else {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/select', item.lead_id);
  }
};

const openFunnel = () => router.push(accountScopedRoute('ramon_funil'));
const exitFocus = () => router.push(accountScopedRoute('ramon_index'));

// Atalhos do Modo Foco (mudos em campo focado — o composable cuida disso;
// a página não tem modais). isActing segue guardando o duplo-acionamento.
const canAct = () => !isLoading.value && !hasError.value && !!current.value;

useKeyboardEvents({
  KeyC: {
    action: () => {
      if (canAct()) openConversation();
    },
  },
  KeyF: {
    action: () => {
      if (canAct()) markDone();
    },
  },
  KeyA: {
    action: () => {
      if (canAct()) snooze();
    },
  },
  Space: {
    action: e => {
      if (!canAct()) return;
      e.preventDefault();
      skip();
    },
  },
  Escape: {
    action: exitFocus,
  },
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto ramon-rail p-4 sm:px-10 sm:py-6"
  >
    <!-- Topo: título + progresso do dia + valor em jogo + sair -->
    <div class="flex flex-wrap items-center gap-4 mb-7">
      <h1
        class="font-cormorant text-[22px] font-semibold leading-none text-n-slate-12"
      >
        {{ t('RAMON.ESTEIRA.FOCUS_TITLE') }}
      </h1>
      <div
        class="flex items-center flex-1 min-w-[160px] gap-2.5"
        data-testid="esteira-progress"
      >
        <span
          class="block flex-1 h-[5px] overflow-hidden rounded-full bg-n-alpha-2"
        >
          <span
            class="block h-full rounded-full bg-gradient-to-r from-[#8a5c33] to-[#c9a97c] transition-all duration-200"
            :style="{ width: `${progressPct}%` }"
          />
        </span>
        <span
          class="text-[13px] font-semibold tabular-nums text-n-iris-11 whitespace-nowrap"
        >
          {{
            t('RAMON.ESTEIRA.PROGRESS', { done: doneCount, total: dayTotal })
          }}
        </span>
      </div>
      <span class="text-xs text-n-slate-9 whitespace-nowrap">
        {{ t('RAMON.ESTEIRA.AT_STAKE', { value: brl(valueSum) }) }}
      </span>
      <button
        type="button"
        data-testid="esteira-reload"
        :title="t('RAMON.ESTEIRA.RELOAD')"
        class="flex items-center justify-center rounded-full size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-50 disabled:pointer-events-none"
        :disabled="isLoading"
        @click="fetchEsteira"
      >
        <span class="i-lucide-refresh-cw size-4" />
      </button>
      <button
        type="button"
        data-testid="esteira-exit"
        class="px-2.5 py-1 text-[11px] rounded-full border border-n-weak text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
        @click="exitFocus"
      >
        {{ t('RAMON.ESTEIRA.FOCUS_EXIT') }}
      </button>
    </div>

    <div v-if="isLoading" class="flex flex-col gap-5 animate-pulse">
      <div class="grid grid-cols-1 lg:grid-cols-[1.3fr_1fr] gap-5">
        <div class="h-96 rounded-2xl bg-n-solid-2" />
        <div class="flex flex-col gap-3">
          <div v-for="n in 3" :key="n" class="h-28 rounded-xl bg-n-solid-2" />
        </div>
      </div>
    </div>

    <!-- Erro de carga: distinto do estado "esteira zerada" -->
    <div
      v-else-if="hasError"
      data-testid="esteira-error"
      class="py-10 text-center border rounded-xl border-n-weak bg-n-solid-2 max-w-2xl"
    >
      <p class="text-sm text-n-ruby-11">
        {{ t('RAMON.ESTEIRA.LOAD_ERROR') }}
      </p>
      <button
        type="button"
        data-testid="esteira-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="fetchEsteira"
      >
        {{ t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <!-- Esteira zerada -->
    <div
      v-else-if="!current"
      data-testid="esteira-empty"
      class="py-10 text-center border rounded-xl border-n-weak bg-n-solid-2 max-w-2xl"
    >
      <span
        class="inline-flex items-center justify-center mb-3 rounded-full size-12 bg-n-teal-3 text-n-teal-11"
      >
        <span class="i-lucide-check-check size-6" />
      </span>
      <p class="text-lg font-medium text-n-slate-12">
        {{ t('RAMON.ESTEIRA.EMPTY_TITLE') }}
      </p>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('RAMON.ESTEIRA.EMPTY_BODY') }}
      </p>
      <button
        type="button"
        data-testid="esteira-empty-cta"
        class="inline-flex items-center h-9 gap-2 px-4 mt-5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
        @click="openFunnel"
      >
        {{ t('RAMON.ESTEIRA.EMPTY_CTA') }}
      </button>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-[1.3fr_1fr] gap-5">
      <!-- Card hero: o item atual -->
      <div
        data-testid="esteira-current"
        class="flex flex-col p-6 rounded-2xl border border-[#c9a97c]/25 bg-gradient-to-br from-n-solid-3 to-n-surface-1 shadow-[0_8px_28px_rgba(0,0,0,0.4)]"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p
              class="text-[10.5px] font-semibold tracking-[.14em] uppercase text-n-iris-11"
            >
              {{
                t('RAMON.ESTEIRA.SUGGESTED', {
                  action: t(
                    `RAMON.ESTEIRA.ACTION.${current.suggested_action.toUpperCase()}`
                  ),
                })
              }}
            </p>
            <p
              class="mt-1 font-cormorant text-[34px] font-semibold leading-[1.05] text-n-slate-12"
            >
              {{ current.name }}
            </p>
          </div>
          <span
            v-if="current.value"
            class="flex-none text-base font-semibold tabular-nums text-n-iris-11"
          >
            {{ money(current.value) }}
          </span>
        </div>

        <div data-testid="esteira-reasons" class="flex flex-wrap gap-1.5 mt-3">
          <span
            v-for="reason in current.reasons"
            :key="reason.key"
            class="px-2.5 py-0.5 text-[11px] rounded-full"
            :class="reasonChipClass(reason.key)"
          >
            {{ reasonLabel(reason) }}
          </span>
          <span
            v-if="current.stage_name"
            class="px-2.5 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ current.stage_name }}
          </span>
        </div>

        <!-- Script do playbook da tese -->
        <div
          v-if="showScript"
          data-testid="esteira-script"
          class="mt-4 p-4 rounded-xl bg-n-alpha-2 border border-[#c9a97c]/10"
        >
          <p
            class="text-[10.5px] font-semibold tracking-[.1em] uppercase text-n-slate-10"
          >
            {{
              t('RAMON.ESTEIRA.SCRIPT_TITLE', { thesis: thesis?.name || '' })
            }}
          </p>
          <div
            v-for="item in scriptItems"
            :key="item.id"
            class="mt-2"
            data-testid="esteira-script-item"
          >
            <p class="text-[13px] leading-relaxed text-n-slate-11">
              {{ item.content }}
            </p>
            <button
              type="button"
              class="mt-1 text-[11px] text-n-iris-11 hover:underline"
              :data-testid="`esteira-script-copy-${item.id}`"
              @click="copyScript(item)"
            >
              {{
                copiedId === item.id
                  ? t('RAMON.PLAYBOOK.COPIED')
                  : t('RAMON.PLAYBOOK.COPY')
              }}
            </button>
          </div>
          <template v-if="objecaoItems.length">
            <button
              type="button"
              data-testid="esteira-script-objections-toggle"
              class="mt-2 text-[11px] text-n-iris-11 hover:underline"
              @click="objecoesOpen = !objecoesOpen"
            >
              {{
                objecoesOpen
                  ? t('RAMON.ESTEIRA.SCRIPT_OBJECTIONS_HIDE')
                  : t('RAMON.ESTEIRA.SCRIPT_OBJECTIONS_SHOW')
              }}
            </button>
            <div v-if="objecoesOpen" data-testid="esteira-script-objections">
              <div v-for="item in objecaoItems" :key="item.id" class="mt-2">
                <p class="text-[13px] leading-relaxed text-n-slate-11">
                  {{ item.content }}
                </p>
                <button
                  type="button"
                  class="mt-1 text-[11px] text-n-iris-11 hover:underline"
                  @click="copyScript(item)"
                >
                  {{
                    copiedId === item.id
                      ? t('RAMON.PLAYBOOK.COPIED')
                      : t('RAMON.PLAYBOOK.COPY')
                  }}
                </button>
              </div>
            </div>
          </template>
        </div>

        <!-- Ações com atalho visível -->
        <div class="flex flex-wrap items-center gap-2.5 pt-5 mt-auto">
          <button
            type="button"
            data-testid="esteira-open-conversation"
            class="inline-flex items-center h-10 gap-2 px-5 text-sm font-semibold rounded-[11px] bg-n-iris-9 text-white hover:bg-n-iris-10 shadow-md"
            @click="openConversation"
          >
            {{
              current.conversation_id
                ? t('RAMON.ESTEIRA.OPEN_CONVERSATION')
                : t('RAMON.ESTEIRA.OPEN_LIFELINE')
            }}
            <kbd
              class="px-1 text-[10px] font-sans rounded border border-white/25 bg-white/10"
            >
              {{ t('RAMON.ESTEIRA.KEY.OPEN') }}
            </kbd>
          </button>
          <button
            type="button"
            data-testid="esteira-done"
            class="inline-flex items-center h-10 gap-2 px-4 text-sm font-semibold rounded-[11px] bg-n-teal-9 text-white hover:bg-n-teal-10 disabled:opacity-50"
            :disabled="isActing"
            @click="markDone"
          >
            {{ t('RAMON.ESTEIRA.DONE') }}
            <kbd
              class="px-1 text-[10px] font-sans rounded border border-white/25 bg-white/10"
            >
              {{ t('RAMON.ESTEIRA.KEY.DONE') }}
            </kbd>
          </button>
          <button
            type="button"
            data-testid="esteira-snooze"
            class="inline-flex items-center h-10 gap-2 px-4 text-sm rounded-[11px] border border-[#c9a97c]/20 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isActing"
            @click="snooze"
          >
            {{ t('RAMON.ESTEIRA.SNOOZE') }}
            <kbd
              class="px-1 text-[10px] font-sans rounded border border-n-weak text-n-slate-10"
            >
              {{ t('RAMON.ESTEIRA.KEY.SNOOZE') }}
            </kbd>
          </button>
          <button
            type="button"
            data-testid="esteira-skip"
            class="inline-flex items-center h-10 gap-2 px-3.5 ml-auto text-[13px] rounded-[11px] text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="skip"
          >
            {{ t('RAMON.ESTEIRA.SKIP') }}
            <kbd
              class="px-1 text-[10px] font-sans rounded border border-n-weak text-n-slate-10"
            >
              {{ t('RAMON.ESTEIRA.KEY.SKIP') }}
            </kbd>
          </button>
        </div>
      </div>

      <!-- Coluna de contexto -->
      <div class="flex flex-col gap-3 min-w-0">
        <!-- Última mensagem -->
        <div
          v-if="lastMessage"
          data-testid="esteira-last-message"
          class="p-4 rounded-xl border border-n-weak bg-n-solid-2"
        >
          <p
            class="mb-2 text-[10.5px] font-semibold tracking-[.1em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.ESTEIRA.LAST_MESSAGE') }} · {{ lastMessageTime }}
          </p>
          <div
            class="p-3 rounded-xl max-w-[90%] bg-n-alpha-2"
            :class="
              lastMessage.incoming ? 'rounded-tl-sm' : 'rounded-tr-sm ml-auto'
            "
          >
            <p class="text-[12.5px] leading-relaxed text-n-slate-11">
              {{ lastMessage.content }}
            </p>
          </div>
        </div>

        <!-- Simulador · última simulação -->
        <div
          data-testid="esteira-last-simulation"
          class="p-4 rounded-xl border border-n-weak bg-n-solid-2"
        >
          <p
            class="mb-1.5 text-[10.5px] font-semibold tracking-[.1em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.ESTEIRA.LAST_SIMULATION') }}
          </p>
          <template v-if="sim">
            <div class="flex items-baseline gap-2">
              <span
                class="font-cormorant text-2xl font-semibold text-n-slate-12"
              >
                {{ money(sim.atrasados) }}
              </span>
              <span class="text-[11px] text-n-slate-10">
                {{ t('RAMON.ESTEIRA.LAST_SIMULATION_HINT') }}
              </span>
            </div>
            <p
              v-if="simParamsLine"
              class="mt-1 text-[11px] text-n-slate-9"
              data-testid="esteira-sim-params"
            >
              {{ simParamsLine }}
            </p>
            <p v-if="simDate" class="mt-0.5 text-[11px] text-n-slate-9">
              {{ t('RAMON.ESTEIRA.LAST_SIMULATION_AT', { date: simDate }) }}
            </p>
          </template>
          <p
            v-else
            class="text-xs text-n-slate-10"
            data-testid="esteira-sim-empty"
          >
            {{ t('RAMON.ESTEIRA.LAST_SIMULATION_EMPTY') }}
          </p>
        </div>

        <!-- Depois desta -->
        <div
          v-if="nextThree.length"
          data-testid="esteira-after-this"
          class="p-4 rounded-xl border border-n-weak bg-n-solid-2"
        >
          <p
            class="mb-2 text-[10.5px] font-semibold tracking-[.1em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.ESTEIRA.AFTER_THIS') }}
          </p>
          <div class="flex flex-col gap-1">
            <button
              v-for="(item, index) in nextThree"
              :key="item.lead_id"
              type="button"
              data-testid="esteira-next-item"
              class="flex items-center w-full gap-2.5 px-1.5 py-1 text-left rounded-lg hover:bg-n-alpha-2"
              @click="jumpTo(index)"
            >
              <span
                class="flex-none rounded-full size-[5px]"
                :class="severityDotClass(item)"
              />
              <span class="text-[12.5px] truncate text-n-slate-11">
                {{ item.name }}
              </span>
              <span
                class="flex-shrink-0 ml-auto text-[11px] tabular-nums text-n-slate-9"
              >
                {{ item.value ? brl(item.value) : '—' }}
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
