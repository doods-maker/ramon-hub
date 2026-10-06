<script setup>
// "+ Adicionar passo" (mockup .paleta): grupos com só o que a B1 executa.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { MENU, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PALETA, PASSOS } from './fluxo';

const emit = defineEmits(['escolher', 'fechar']);
const { t } = useI18n();
const raiz = ref(null);
onClickOutside(raiz, () => emit('fechar'));

const iconeDo = item =>
  item.chave === 'atribuir' ? 'i-lucide-user-check' : PASSOS[item.tipo].icone;
</script>

<template>
  <div
    ref="raiz"
    :class="MENU"
    class="absolute left-3.5 top-14 z-10 max-h-[calc(100%-120px)] w-[270px] overflow-y-auto"
    data-testid="fluxo-paleta"
  >
    <template v-for="grupo in PALETA" :key="grupo.grupo">
      <h4
        class="mx-1.5 mb-1 mt-2.5 text-[11.5px] font-medium text-n-slate-10 first:mt-1"
      >
        {{ t(`CAPTAIN_RAMON.FLUXOS.GRUPOS.${grupo.grupo}`) }}
      </h4>
      <button
        v-for="item in grupo.itens"
        :key="item.chave"
        type="button"
        class="flex w-full items-center gap-2.5 rounded-lg p-1.5 text-left text-[13px] text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('escolher', item)"
      >
        <span
          class="grid size-6 place-items-center rounded-md"
          :class="TOM[PASSOS[item.tipo].tom]"
        >
          <i :class="iconeDo(item)" class="size-3.5" />
        </span>
        {{ t(`CAPTAIN_RAMON.FLUXOS.PALETA.${item.chave}`) }}
      </button>
    </template>
  </div>
</template>
