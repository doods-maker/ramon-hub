<script setup>
// Números da Etapa (últimos 30 dias, só deste alvo — Ramon::PerfilIa::Numeros) e o aviso "Passar pra Sozinha?".
// O botão só emite: quem move o Marcador (ajuste não salvo) é a página.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  etapa: { type: Object, required: true },
  // { enviadas, rascunhos: { igual, editado, descartado }, chamou_equipe, sugerir_sozinha } ou null = sem dados
  numeros: { type: Object, default: null },
  sugerir: { type: Boolean, default: false },
});
const emit = defineEmits(['sozinha']);
const { t } = useI18n();
const K = 'RAMON.COMO_IA.NUMEROS';

const revisados = computed(() =>
  Object.values(props.numeros?.rascunhos || {}).reduce((a, b) => a + b, 0)
);
</script>

<template>
  <div data-testid="numeros" class="flex flex-col gap-2 mt-4">
    <p class="text-xs font-medium text-n-slate-10">
      {{ t(`${K}.TITULO`, { etapa: etapa.nome }) }}
    </p>
    <p
      v-if="!numeros"
      data-testid="numeros-vazio"
      class="text-[12.5px] text-n-slate-10"
    >
      {{ t(`${K}.SEM_DADOS`) }}
    </p>
    <div
      v-else
      data-testid="numeros-linha"
      class="flex flex-wrap gap-x-4 gap-y-1 text-[12.5px] text-n-slate-11"
    >
      <span>{{ t(`${K}.ENVIADAS`, { n: numeros.enviadas }) }}</span>
      <span>{{ t(`${K}.RASCUNHOS`, numeros.rascunhos) }}</span>
      <span>{{ t(`${K}.EQUIPE`, { n: numeros.chamou_equipe }) }}</span>
    </div>
    <div
      v-if="sugerir"
      data-testid="sugestao-sozinha"
      class="flex flex-wrap items-center gap-3 px-3.5 py-3 text-[13px] rounded-xl"
      :class="TOM.teal"
    >
      <span class="i-lucide-sparkles size-4 shrink-0" aria-hidden="true" />
      <span class="flex-1 min-w-0 text-n-slate-12">
        {{
          t(`${K}.SUGESTAO`, {
            etapa: etapa.nome,
            igual: numeros.rascunhos.igual,
            n: revisados,
          })
        }}
      </span>
      <Button
        size="sm"
        variant="faded"
        color="teal"
        :label="t(`${K}.PASSAR`)"
        data-testid="passar-sozinha"
        @click="emit('sozinha')"
      />
    </div>
  </div>
</template>
