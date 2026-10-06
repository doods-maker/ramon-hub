<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import ReunioesAPI from 'dashboard/api/reunioes';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ReuniaoRecorder from '../components/reunioes/ReuniaoRecorder.vue';
import ReuniaoDetalhe from '../components/reunioes/ReuniaoDetalhe.vue';
import { CAMPO, CARTAO, CHIP, LINHA, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonReunioes' });

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const reunioes = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const reuniaoId = computed(() => route.params.reuniaoId);

// Busca no servidor (título ou nome do lead), com respiro de 300ms.
const busca = ref('');
let buscaTimer = null;
const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReunioesAPI.buscar(busca.value.trim());
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
const STATUS_TOM = { transcrevendo: 'amber', pronta: 'teal', erro: 'ruby' };
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
watch(busca, () => {
  clearTimeout(buscaTimer);
  buscaTimer = setTimeout(carregar, 300);
});

// O router reusa a instância entre lista e detalhe (mesmo componente); sem
// isso, voltar do detalhe mostra a lista desatualizada (padrão do Calculos.vue).
watch(reuniaoId, id => {
  if (!id) carregar();
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="flex flex-col w-full max-w-3xl mx-auto">
      <template v-if="!reuniaoId">
        <RamonPageHeader :title="t('RAMON.REUNIOES.TITLE')" />
        <ReuniaoRecorder
          class="mb-6"
          :lead-id="route.query.leadId"
          @created="onCreated"
        />
        <input
          v-model="busca"
          type="search"
          data-testid="reunioes-busca"
          :class="CAMPO"
          class="!mb-3"
          :placeholder="t('RAMON.REUNIOES.SEARCH_PLACEHOLDER')"
        />
        <div
          v-if="isLoading && !reunioes.length"
          class="flex flex-col gap-3 animate-pulse"
          data-testid="reunioes-skeleton"
        >
          <div class="h-12 rounded-xl bg-n-alpha-2" />
          <div class="h-12 rounded-xl bg-n-alpha-2" />
          <div class="h-12 rounded-xl bg-n-alpha-2" />
        </div>
        <div
          v-else-if="hasError"
          class="flex items-center gap-2 text-sm text-n-ruby-11"
        >
          {{ t('RAMON.REUNIOES.LOAD_ERROR') }}
          <Button
            link
            xs
            :label="t('RAMON.LEAD_PANEL.RETRY')"
            @click="carregar"
          />
        </div>
        <p v-else-if="!reunioes.length" class="text-sm text-n-slate-10">
          {{
            busca.trim()
              ? t('RAMON.REUNIOES.SEARCH_EMPTY')
              : t('RAMON.REUNIOES.EMPTY')
          }}
        </p>
        <ul
          v-else
          :class="CARTAO"
          class="flex flex-col !p-1.5 list-none reset-base ms-0"
        >
          <li
            v-for="(reuniao, index) in reunioes"
            :key="reuniao.id"
            :class="{ 'border-t border-n-weak': index > 0 }"
          >
            <button
              type="button"
              :class="LINHA"
              class="flex items-center gap-4 !px-3 !py-2.5"
              data-testid="reunioes-item"
              @click="abrir(reuniao.id)"
            >
              <span class="flex flex-col flex-1 min-w-0">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ reuniao.titulo }}
                </span>
                <span
                  v-if="reuniao.lead_name"
                  class="flex items-center gap-1 text-xs truncate text-n-slate-10"
                  data-testid="reunioes-item-lead"
                >
                  <span class="i-lucide-user size-3 shrink-0" />
                  {{ reuniao.lead_name }}
                </span>
              </span>
              <span class="font-mono text-xs tabular-nums text-n-slate-10">
                {{ formatoDuracao(reuniao.duracao_segundos) }}
              </span>
              <span class="font-mono text-xs tabular-nums text-n-slate-10">
                {{ formatoData(reuniao.created_at) }}
              </span>
              <span :class="[CHIP, TOM[STATUS_TOM[reuniao.status]]]">
                {{ statusLabel(reuniao.status) }}
              </span>
            </button>
          </li>
        </ul>
      </template>
      <template v-else>
        <Button
          ghost
          slate
          sm
          icon="i-lucide-arrow-left"
          class="self-start mb-4 -ms-3"
          :label="t('RAMON.REUNIOES.BACK')"
          @click="router.push({ name: 'ramon_reunioes' })"
        />
        <ReuniaoDetalhe
          :reuniao-id="reuniaoId"
          @deleted="router.push({ name: 'ramon_reunioes' })"
        />
      </template>
    </div>
  </div>
</template>
