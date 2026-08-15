<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import ReunioesAPI from 'dashboard/api/reunioes';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ReuniaoRecorder from '../components/reunioes/ReuniaoRecorder.vue';
import ReuniaoDetalhe from '../components/reunioes/ReuniaoDetalhe.vue';

defineOptions({ name: 'RamonReunioes' });

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const reunioes = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const reuniaoId = computed(() => route.params.reuniaoId);

const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReunioesAPI.get();
    reunioes.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const abrir = id => {
  router.push({ name: 'ramon_reuniao', params: { reuniaoId: id } });
};

const onCreated = reuniao => abrir(reuniao.id);

const STATUS_LABEL = {
  transcrevendo: 'RAMON.REUNIOES.STATUS_TRANSCREVENDO',
  pronta: 'RAMON.REUNIOES.STATUS_PRONTA',
  erro: 'RAMON.REUNIOES.STATUS_ERRO',
};
const statusLabel = status => t(STATUS_LABEL[status]);

const formatoData = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const formatoDuracao = total => {
  if (!total) return '—';
  const min = Math.floor(total / 60);
  return `${min}min`;
};

onMounted(carregar);

// O router reusa a instância entre lista e detalhe (mesmo componente); sem
// isso, voltar do detalhe mostra a lista desatualizada (padrão do Calculos.vue).
watch(reuniaoId, id => {
  if (!id) carregar();
});
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto p-8">
    <template v-if="!reuniaoId">
      <RamonPageHeader :title="t('RAMON.REUNIOES.TITLE')" />
      <ReuniaoRecorder
        class="mb-6"
        :lead-id="route.query.leadId"
        @created="onCreated"
      />
      <div
        v-if="isLoading"
        class="flex flex-col gap-3 animate-pulse"
        data-testid="reunioes-skeleton"
      >
        <div class="h-12 rounded-lg bg-n-solid-2" />
        <div class="h-12 rounded-lg bg-n-solid-2" />
        <div class="h-12 rounded-lg bg-n-solid-2" />
      </div>
      <div
        v-else-if="hasError"
        class="flex items-center gap-2 text-sm text-n-ruby-11"
      >
        {{ t('RAMON.REUNIOES.LOAD_ERROR') }}
        <button
          type="button"
          class="text-n-iris-11 hover:underline"
          @click="carregar"
        >
          {{ t('RAMON.LEAD_PANEL.RETRY') }}
        </button>
      </div>
      <p v-else-if="!reunioes.length" class="text-sm text-n-slate-11">
        {{ t('RAMON.REUNIOES.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col divide-y divide-n-weak">
        <li v-for="reuniao in reunioes" :key="reuniao.id">
          <button
            type="button"
            class="flex w-full items-center justify-between gap-4 py-3 text-start"
            @click="abrir(reuniao.id)"
          >
            <span
              class="min-w-0 flex-1 truncate text-sm font-medium text-n-slate-12"
            >
              {{ reuniao.titulo }}
            </span>
            <span class="text-xs text-n-slate-11">{{
              formatoDuracao(reuniao.duracao_segundos)
            }}</span>
            <span class="text-xs text-n-slate-11">{{
              formatoData(reuniao.created_at)
            }}</span>
            <span
              class="rounded-full px-2 py-0.5 text-xs"
              :class="{
                'bg-n-teal-3 text-n-teal-11': reuniao.status === 'pronta',
                'bg-n-amber-3 text-n-amber-11':
                  reuniao.status === 'transcrevendo',
                'bg-n-ruby-3 text-n-ruby-11': reuniao.status === 'erro',
              }"
            >
              {{ statusLabel(reuniao.status) }}
            </span>
          </button>
        </li>
      </ul>
    </template>
    <template v-else>
      <button
        type="button"
        class="mb-4 self-start text-sm text-n-iris-11 hover:underline"
        @click="router.push({ name: 'ramon_reunioes' })"
      >
        {{ t('RAMON.REUNIOES.BACK') }}
      </button>
      <ReuniaoDetalhe
        :reuniao-id="reuniaoId"
        @deleted="router.push({ name: 'ramon_reunioes' })"
      />
    </template>
  </div>
</template>
