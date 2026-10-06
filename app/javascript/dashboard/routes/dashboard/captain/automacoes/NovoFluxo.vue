<script setup>
// Modal "Novo fluxo" (mockup tela 4): em branco + modelos prontos.
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  FUNDO_JANELA,
  JANELA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { MODELOS } from './modelos';

defineProps({ ocupado: { type: Boolean, default: false } });
const emit = defineEmits(['criar', 'fechar']);
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[720px] !p-0">
      <div class="flex items-center border-b border-n-weak px-5 py-4">
        <h2 class="text-[15px] font-semibold text-n-slate-12">
          {{ t('CAPTAIN_RAMON.FLUXOS.NOVO') }}
        </h2>
        <Button
          class="ml-auto"
          ghost
          slate
          xs
          icon="i-lucide-x"
          :title="t('CAPTAIN_RAMON.FLUXOS.FECHAR')"
          @click="emit('fechar')"
        />
      </div>
      <div class="grid grid-cols-1 gap-2.5 p-5 sm:grid-cols-2">
        <button
          v-for="modelo in MODELOS"
          :key="modelo.chave"
          type="button"
          data-testid="fluxo-modelo"
          :disabled="ocupado"
          class="flex gap-3 rounded-xl border border-n-weak p-3 text-left hover:border-n-blue-9 hover:bg-n-blue-9/[0.08] disabled:cursor-wait disabled:opacity-60"
          :class="modelo.chave === 'branco' ? 'border-dashed' : ''"
          @click="emit('criar', modelo)"
        >
          <span
            class="grid size-[30px] shrink-0 place-items-center rounded-lg bg-n-alpha-2 text-n-slate-11"
          >
            <i :class="modelo.icone" class="size-4" />
          </span>
          <span>
            <b class="block text-[13.5px] font-medium text-n-slate-12">
              {{ t(`CAPTAIN_RAMON.FLUXOS.MODELOS.${modelo.chave}.NOME`) }}
            </b>
            <span class="text-[12.5px] text-n-slate-11">
              {{ t(`CAPTAIN_RAMON.FLUXOS.MODELOS.${modelo.chave}.DESCRICAO`) }}
            </span>
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
