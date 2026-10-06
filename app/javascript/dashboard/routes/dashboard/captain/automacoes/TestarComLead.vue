<script setup>
// "Testar com um lead…": ensaio do rascunho num lead/conversa real (spec §6).
// Fluxo de gatilho manual, publicado e ligado também pode "Rodar de verdade".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke, useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadsAPI from 'dashboard/api/leads';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  AVISO,
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  RODAPE_JANELA,
  TITULO_JANELA,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineProps({
  erros: { type: Array, default: () => [] },
  ocupado: { type: Boolean, default: false },
  podeRodar: { type: Boolean, default: false },
});
const emit = defineEmits(['ensaiar', 'rodar', 'fechar']);
const K = 'CAPTAIN_RAMON.FLUXOS.TESTAR';
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));

const modo = ref('lead');
const busca = ref('');
const leads = ref([]);
const lead = ref(null);
const conversa = ref('');

const buscar = useDebounceFn(async () => {
  if (busca.value.trim().length < 2) {
    leads.value = [];
    return;
  }
  const { data } = await LeadsAPI.get({ q: busca.value.trim() });
  leads.value = data.payload.slice(0, 8);
}, 300);

const alvo = computed(() => {
  if (modo.value === 'lead')
    return lead.value ? { lead_id: lead.value.id } : null;
  return conversa.value ? { conversation_id: Number(conversa.value) } : null;
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[28rem]">
      <h3 :class="TITULO_JANELA">{{ t(`${K}.TITULO`) }}</h3>
      <p class="mb-3 text-xs text-n-slate-11">{{ t(`${K}.AJUDA`) }}</p>
      <div class="mb-3 flex border-b border-n-weak">
        <button
          type="button"
          :class="[ABA, modo === 'lead' ? ABA_ATIVA : ABA_INATIVA]"
          @click="modo = 'lead'"
        >
          {{ t(`${K}.LEAD`) }}
        </button>
        <button
          type="button"
          :class="[ABA, modo === 'conversa' ? ABA_ATIVA : ABA_INATIVA]"
          @click="modo = 'conversa'"
        >
          {{ t(`${K}.CONVERSA`) }}
        </button>
      </div>

      <template v-if="modo === 'lead'">
        <input
          v-model="busca"
          :class="CAMPO"
          :placeholder="t(`${K}.BUSCAR`)"
          @input="buscar"
        />
        <div class="mt-2 flex max-h-56 flex-col overflow-y-auto">
          <button
            v-for="l in leads"
            :key="l.id"
            type="button"
            :class="[LINHA, lead?.id === l.id ? TOM.blue : '']"
            @click="lead = l"
          >
            {{ l.name }}
            <span class="font-mono text-xs text-n-slate-10">#{{ l.id }}</span>
          </button>
        </div>
      </template>
      <input
        v-else
        v-model="conversa"
        :class="CAMPO"
        type="number"
        min="1"
        :placeholder="t(`${K}.NUMERO_CONVERSA`)"
      />

      <div v-if="erros.length" :class="[AVISO, TOM.ruby]" class="mt-3">
        <p v-for="e in erros" :key="e">{{ e }}</p>
      </div>
      <p v-if="podeRodar" class="mt-3 text-xs text-n-slate-10">
        {{ t(`${K}.RODAR_AJUDA`) }}
      </p>

      <div :class="RODAPE_JANELA">
        <Button
          slate
          faded
          sm
          :label="t(`${K}.CANCELAR`)"
          @click="emit('fechar')"
        />
        <Button
          v-if="podeRodar"
          amber
          outline
          sm
          :label="t(`${K}.RODAR`)"
          :disabled="!alvo || ocupado"
          @click="emit('rodar', alvo)"
        />
        <Button
          sm
          icon="i-lucide-flask-conical"
          :label="t(`${K}.ENSAIAR`)"
          :is-loading="ocupado"
          :disabled="!alvo"
          @click="emit('ensaiar', alvo)"
        />
      </div>
    </div>
  </div>
</template>
