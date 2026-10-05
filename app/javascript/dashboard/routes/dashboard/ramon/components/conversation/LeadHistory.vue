<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { CARTAO } from '../../helpers/ui';
import ListaAtividades from './ListaAtividades.vue';

// "Atividade recente" (item Atividade do painel): carrega e entrega as linhas
// pra ListaAtividades (a mesma da linha do tempo do Dossiê).
const props = defineProps({
  leadId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadHistory' });

const store = useStore();
const stages = useMapGetter('leadConfig/getStages');
const activities = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const load = async () => {
  // zera antes de buscar: nunca mostrar a timeline do lead anterior
  activities.value = [];
  isLoading.value = true;
  hasError.value = false;
  try {
    activities.value = await store.dispatch(
      'leads/fetchActivities',
      Number(props.leadId)
    );
  } catch (e) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};
watch(() => props.leadId, load, { immediate: true });
</script>

<template>
  <div data-testid="lead-history" :class="CARTAO">
    <p class="flex items-center gap-1.5 text-sm font-semibold text-n-slate-12">
      <span class="i-lucide-activity size-4 text-n-slate-10" />
      {{ $t('RAMON.LEAD_PANEL.HISTORY.TITLE') }}
    </p>
    <p
      v-if="isLoading"
      data-testid="history-loading"
      class="flex items-center gap-2 mt-3 text-xs text-n-slate-9"
    >
      <Spinner :size="14" />
      {{ $t('RAMON.LEAD_PANEL.HISTORY.LOADING') }}
    </p>
    <template v-else-if="hasError">
      <p data-testid="history-error" class="mt-3 text-xs text-n-ruby-11">
        {{ $t('RAMON.LEAD_PANEL.HISTORY.LOAD_ERROR') }}
      </p>
      <Button
        data-testid="history-retry"
        link
        xs
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="load"
      />
    </template>
    <p
      v-else-if="!activities.length"
      data-testid="history-empty"
      class="mt-3 text-xs text-n-slate-9"
    >
      {{ $t('RAMON.LEAD_PANEL.HISTORY.EMPTY') }}
    </p>
    <ListaAtividades
      v-else
      :activities="[...activities].reverse()"
      :stages="stages || []"
    />
  </div>
</template>
