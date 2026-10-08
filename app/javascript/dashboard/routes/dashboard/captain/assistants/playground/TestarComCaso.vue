<script setup>
// "Testar com o caso…" (I-PG4): acha o lead pelo nome e devolve para a página pôr o nº do caso na mensagem.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import LeadsAPI from 'dashboard/api/leads';
import {
  CAMPO,
  LINHA,
  MENU,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const emit = defineEmits(['escolher']);
const { t } = useI18n();

const busca = ref('');
const leads = ref([]);
const buscou = ref(false);

// só a última busca vale (mesmo cuidado do "Testar com um lead" das Automações)
let pedido = 0;
const buscar = useDebounceFn(async () => {
  pedido += 1;
  const meu = pedido;
  const termo = busca.value.trim();
  if (termo.length < 2) {
    leads.value = [];
    buscou.value = false;
    return;
  }
  try {
    const { data } = await LeadsAPI.get({ q: termo });
    if (meu !== pedido) return;
    leads.value = data.payload.slice(0, 6);
    buscou.value = true;
  } catch (e) {
    if (meu === pedido) leads.value = [];
  }
}, 300);

const escolher = lead => {
  emit('escolher', lead);
  busca.value = '';
  leads.value = [];
  buscou.value = false;
};
</script>

<template>
  <div class="relative">
    <input
      v-model="busca"
      data-testid="testar-caso-busca"
      :class="CAMPO"
      :placeholder="t('INTEL.TESTAR.CASO_PLACEHOLDER')"
      :title="t('INTEL.TESTAR.CASO_AJUDA')"
      @input="buscar"
    />
    <ul v-if="buscou" class="absolute z-10 w-full mt-1 list-none" :class="MENU">
      <li v-for="lead in leads" :key="lead.id">
        <button
          type="button"
          data-testid="testar-caso-opcao"
          :class="LINHA"
          @click="escolher(lead)"
        >
          {{ lead.name }}
          <span class="font-mono text-xs text-n-slate-10">#{{ lead.id }}</span>
        </button>
      </li>
      <li v-if="!leads.length" class="px-2 py-1.5 text-xs text-n-slate-10">
        {{ t('INTEL.TESTAR.CASO_NENHUM') }}
      </li>
    </ul>
  </div>
</template>
