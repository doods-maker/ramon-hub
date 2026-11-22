<script setup>
// "Quem atende nas etapas de ganho": o assistente de cada Etapa de ganho (Etapa
// Documentos); vazio = o da caixa. Vale para o escritório todo (é da Etapa, não
// do Perfil), por isso fica ao lado dos Limites gerais. Veio da Configuração do
// Funil (Inteligência num lugar só, 2026-11-22). Sem Captain/assistentes ou com
// a chave da etapa Documentos desligada, o bloco nem aparece.
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import { mensagemErro } from 'dashboard/routes/dashboard/ramon/helpers/erro';
import { CAMPO } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const store = useStore();
const { t } = useI18n();
const K = 'RAMON.COMO_IA.ASSISTENTE_ETAPA';

const assistentes = ref([]);
const etapasDeGanho = computed(() =>
  (store.getters['leadConfig/getStages'] || []).filter(s => s.is_won)
);
const visivel = computed(
  () =>
    !!store.getters['leadConfig/getEtapaDocumentos'] &&
    assistentes.value.length > 0 &&
    etapasDeGanho.value.length > 0
);

onMounted(() => {
  if (!(store.getters['leadConfig/getStages'] || []).length)
    store.dispatch('leadConfig/get');
  CaptainAssistantAPI.get()
    .then(({ data }) => {
      assistentes.value = data.payload || [];
    })
    .catch(() => {});
});

const salvar = (stage, raw) => {
  const id = raw === '' ? null : Number(raw);
  if (id === (stage.captain_assistant_id ?? null)) return;
  store
    .dispatch('leadConfig/updateStage', {
      id: stage.id,
      captain_assistant_id: id,
    })
    .catch(e => useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR'))));
};
</script>

<template>
  <div v-if="visivel" data-testid="assistente-por-etapa">
    <div class="flex flex-wrap items-baseline gap-2.5 mb-2.5">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h3>
      <span class="text-[12.5px] text-n-slate-10">{{ t(`${K}.DICA`) }}</span>
    </div>
    <div
      class="flex flex-col gap-2 p-4 border border-solid rounded-xl border-n-weak"
    >
      <label
        v-for="s in etapasDeGanho"
        :key="s.id"
        class="flex items-center justify-between gap-3 text-[13px] text-n-slate-12"
      >
        <span class="truncate">{{ s.name }}</span>
        <select
          :value="s.captain_assistant_id ?? ''"
          data-testid="stage-assistente"
          class="!w-52"
          :class="CAMPO"
          @change="e => salvar(s, e.target.value)"
        >
          <option value="">{{ t(`${K}.DA_CAIXA`) }}</option>
          <option v-for="a in assistentes" :key="a.id" :value="a.id">
            {{ a.name }}
          </option>
        </select>
      </label>
    </div>
  </div>
</template>
