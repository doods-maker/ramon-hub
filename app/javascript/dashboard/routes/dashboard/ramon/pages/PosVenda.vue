<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonPosVendaAPI from 'dashboard/api/ramonPosVenda';
import RamonPageHeader from '../components/RamonPageHeader.vue';

defineOptions({ name: 'RamonPosVenda' });

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const showConcluidos = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonPosVendaAPI.get();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const pendentes = computed(() => data.value?.pendentes ?? []);
const concluidos = computed(() => data.value?.concluidos ?? []);

// Padrão das outras páginas: abre o Funil e seleciona o lead (drawer).
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};

// Abrir conversa (padrão do fork: funil + dock).
const openConversation = conversationId => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/toggleDock', conversationId);
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8"
  >
    <RamonPageHeader
      :title="t('RAMON.POS_VENDA.TITLE')"
      :subtitle="t('RAMON.POS_VENDA.SUBTITLE')"
    />

    <!-- Skeleton no primeiro load -->
    <div
      v-if="loading && !data"
      data-testid="pos-venda-skeleton"
      class="flex flex-col gap-2 animate-pulse"
    >
      <div v-for="i in 5" :key="i" class="h-14 rounded-xl bg-n-solid-2" />
    </div>

    <!-- Erro com retry explícito -->
    <div
      v-else-if="error && !data"
      data-testid="pos-venda-error"
      class="text-sm"
    >
      <p class="text-n-ruby-11">{{ t('RAMON.POS_VENDA.ERROR') }}</p>
      <button
        type="button"
        data-testid="pos-venda-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="fetchData"
      >
        {{ t('RAMON.POS_VENDA.RETRY') }}
      </button>
    </div>

    <template v-else-if="data">
      <!-- Vazio -->
      <p
        v-if="!pendentes.length"
        data-testid="pos-venda-empty"
        class="text-sm text-n-slate-10"
      >
        {{ t('RAMON.POS_VENDA.EMPTY') }}
      </p>

      <!-- Pendentes: mais antigo pro mais novo (ordem vem do backend) -->
      <div v-else class="flex flex-col gap-1.5 max-w-3xl">
        <div
          v-for="item in pendentes"
          :key="item.id"
          data-testid="pos-venda-row"
          class="flex items-center justify-between gap-2.5 px-3 py-2.5 rounded-xl bg-n-solid-2 border border-n-weak border-l-[3px] cursor-pointer hover:bg-n-alpha-2"
          :class="item.dias > 7 ? 'border-l-n-amber-9' : 'border-l-n-weak'"
          @click="openLead(item.id)"
        >
          <div class="min-w-0">
            <p class="text-sm font-medium truncate text-n-slate-12">
              {{ item.name }}
            </p>
            <p class="text-xs truncate text-n-slate-10">
              {{ t('RAMON.POS_VENDA.DIAS', { dias: item.dias }) }} ·
              {{
                t('RAMON.POS_VENDA.DOCS', {
                  received: item.docs_received,
                  total: item.docs_total,
                })
              }}
            </p>
          </div>
          <button
            v-if="item.conversation_id"
            type="button"
            data-testid="pos-venda-open-conversation"
            class="shrink-0 px-2 py-1 text-xs font-medium rounded-md text-n-iris-11 hover:bg-n-alpha-2"
            @click.stop="openConversation(item.conversation_id)"
          >
            {{ t('RAMON.POS_VENDA.OPEN_CONVERSATION') }}
          </button>
        </div>
      </div>

      <!-- Concluídos: colapsado por padrão -->
      <div v-if="concluidos.length" class="mt-6 max-w-3xl">
        <button
          type="button"
          data-testid="pos-venda-toggle-concluidos"
          class="flex items-center gap-1.5 text-sm font-medium text-n-slate-11 hover:text-n-slate-12"
          @click="showConcluidos = !showConcluidos"
        >
          <span
            class="i-lucide-chevron-right size-4 transition-transform"
            :class="showConcluidos ? 'rotate-90' : ''"
          />
          {{ t('RAMON.POS_VENDA.CONCLUIDOS', { count: concluidos.length }) }}
        </button>

        <div v-if="showConcluidos" class="flex flex-col gap-1.5 mt-2">
          <div
            v-for="item in concluidos"
            :key="item.id"
            data-testid="pos-venda-row-concluido"
            class="flex items-center justify-between gap-2.5 px-3 py-2.5 rounded-xl bg-n-solid-2 border border-n-weak cursor-pointer hover:bg-n-alpha-2"
            @click="openLead(item.id)"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="i-lucide-check-circle-2 size-4 shrink-0 text-n-teal-11"
              />
              <p class="text-sm font-medium truncate text-n-slate-12">
                {{ item.name }}
              </p>
            </div>
            <span
              v-if="item.drive_concluido"
              data-testid="pos-venda-drive-chip"
              class="shrink-0 px-2 py-0.5 text-[11px] font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ t('RAMON.POS_VENDA.DRIVE_CHIP') }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
