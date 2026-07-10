<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';
import StatBlock from '../components/command/StatBlock.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// Estado local simples: o item atual é sempre items[0].
// Pular gira a fila; Feito/Adiar removem o item.
const items = ref([]);
const doneCount = ref(0);
const isLoading = ref(true);

const fetchEsteira = async () => {
  isLoading.value = true;
  try {
    const { data } = await RamonEsteiraAPI.get();
    items.value = data.items || [];
    doneCount.value = data.board?.done_today || 0;
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

const total = computed(() => items.value.length);
const valueSum = computed(() =>
  items.value.reduce((sum, item) => sum + (Number(item.value) || 0), 0)
);
const current = computed(() => items.value[0] || null);
const upcoming = computed(() => items.value.slice(1));

// Motivo legível: chaves i18n vindas do backend; moeda formatada aqui.
const reasonLabel = reason =>
  t(
    `RAMON.ESTEIRA.REASON.${reason.key}`,
    reason.key === 'PRESCRIPTION_BLEEDING'
      ? { value: brl(reason.params.monthly) }
      : reason.params
  );
const reasonsText = item => item.reasons.map(reasonLabel).join(' + ');

const skip = () => {
  if (items.value.length > 1) items.value.push(items.value.shift());
};

// Clique na lista dos próximos: traz o item pra frente da fila.
const jumpTo = index => {
  const [item] = items.value.splice(index + 1, 1);
  items.value.unshift(item);
};

const markDone = async () => {
  const item = current.value;
  if (!item) return;
  await RamonEsteiraAPI.done(item.lead_id);
  doneCount.value += 1;
  items.value.shift();
  useAlert(t('RAMON.ESTEIRA.DONE_TOAST'));
};

const snooze = async () => {
  const item = current.value;
  if (!item) return;
  await RamonEsteiraAPI.snooze(item.lead_id, item.task_id);
  items.value.shift();
  useAlert(t('RAMON.ESTEIRA.SNOOZED_TOAST'));
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
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background p-8">
    <RamonPageHeader
      :eyebrow="t('RAMON.ESTEIRA.EYEBROW')"
      :title="t('RAMON.ESTEIRA.TITLE')"
    >
      <template #actions>
        <button
          type="button"
          data-testid="esteira-reload"
          class="flex items-center h-8 gap-2 px-3 text-sm rounded-lg text-n-slate-11 border border-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12"
          :disabled="isLoading"
          @click="fetchEsteira"
        >
          <span class="i-lucide-refresh-cw size-4" />
          {{ t('RAMON.ESTEIRA.RELOAD') }}
        </button>
      </template>
    </RamonPageHeader>

    <div v-if="isLoading" class="flex flex-col gap-6 animate-pulse">
      <div class="grid grid-cols-3 gap-4 max-w-2xl">
        <div
          v-for="n in 3"
          :key="n"
          class="h-[120px] rounded-xl bg-n-solid-2"
        />
      </div>
      <div class="h-56 rounded-xl bg-n-solid-2 max-w-2xl" />
    </div>

    <div v-else class="flex flex-col gap-8 max-w-2xl">
      <!-- Placar do dia -->
      <div class="grid grid-cols-3 gap-4" data-testid="esteira-board">
        <StatBlock :label="t('RAMON.ESTEIRA.BOARD.ACTIONS')" :value="total" />
        <StatBlock
          :label="t('RAMON.ESTEIRA.BOARD.VALUE')"
          :value="brl(valueSum)"
        />
        <StatBlock :label="t('RAMON.ESTEIRA.BOARD.DONE')" :value="doneCount" />
      </div>

      <!-- Item atual -->
      <div
        v-if="current"
        data-testid="esteira-current"
        class="p-6 border rounded-xl border-n-weak bg-n-solid-2"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="font-cormorant text-3xl font-semibold text-n-slate-12">
              {{ current.name }}
            </p>
            <div class="flex flex-wrap items-center gap-1.5 mt-2">
              <span
                v-if="current.stage_name"
                class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ current.stage_name }}
              </span>
              <span
                v-if="current.value"
                class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ brl(current.value) }}
              </span>
            </div>
          </div>
          <span
            class="flex-shrink-0 px-2 py-1 text-[11px] uppercase tracking-wide rounded-lg bg-n-iris-3 text-n-iris-11"
          >
            {{
              t(
                `RAMON.ESTEIRA.ACTION.${current.suggested_action.toUpperCase()}`
              )
            }}
          </span>
        </div>

        <p
          data-testid="esteira-reasons"
          class="mt-4 text-sm text-n-slate-12 bg-n-alpha-2 rounded-lg p-3"
        >
          {{ reasonsText(current) }}
        </p>

        <div
          class="flex flex-wrap items-center gap-2 pt-4 mt-4 border-t border-n-weak"
        >
          <button
            type="button"
            data-testid="esteira-open-conversation"
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
            @click="openConversation"
          >
            <span class="i-lucide-message-square size-4" />
            {{
              current.conversation_id
                ? t('RAMON.ESTEIRA.OPEN_CONVERSATION')
                : t('RAMON.ESTEIRA.OPEN_LIFELINE')
            }}
          </button>
          <button
            type="button"
            data-testid="esteira-done"
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg bg-n-teal-9 text-white hover:bg-n-teal-10"
            @click="markDone"
          >
            <span class="i-lucide-check size-4" />
            {{ t('RAMON.ESTEIRA.DONE') }}
          </button>
          <button
            type="button"
            data-testid="esteira-snooze"
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
            @click="snooze"
          >
            <span class="i-lucide-alarm-clock size-4" />
            {{ t('RAMON.ESTEIRA.SNOOZE') }}
          </button>
          <button
            type="button"
            data-testid="esteira-skip"
            class="inline-flex items-center h-8 gap-1.5 px-3 ml-auto text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="skip"
          >
            {{ t('RAMON.ESTEIRA.SKIP') }}
            <span class="i-lucide-chevron-right size-4" />
          </button>
        </div>
      </div>

      <!-- Esteira zerada -->
      <div
        v-else
        data-testid="esteira-empty"
        class="py-10 text-center border rounded-xl border-n-weak bg-n-solid-2"
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

      <!-- Próximos da fila -->
      <section v-if="upcoming.length">
        <h2 class="mb-3 text-sm tracking-widest uppercase text-n-slate-9">
          {{ t('RAMON.ESTEIRA.NEXT_TITLE') }}
        </h2>
        <ul class="flex flex-col gap-1">
          <li v-for="(item, index) in upcoming" :key="item.lead_id">
            <button
              type="button"
              data-testid="esteira-next-item"
              class="flex items-center w-full gap-3 px-3 py-2 text-left rounded-lg hover:bg-n-alpha-2"
              @click="jumpTo(index)"
            >
              <span class="text-sm truncate text-n-slate-12">
                {{ item.name }}
              </span>
              <span class="text-xs truncate text-n-slate-10">
                {{ reasonLabel(item.reasons[0]) }}
              </span>
              <span
                v-if="item.value"
                class="ml-auto text-xs flex-shrink-0 text-n-slate-11"
              >
                {{ brl(item.value) }}
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
