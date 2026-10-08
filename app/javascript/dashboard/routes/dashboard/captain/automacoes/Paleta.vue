<script setup>
// "+ Adicionar passo" (mockup .paleta): grupos com só o que a B1 executa.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { MENU, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PALETA, PASSOS, PASSOS_CONTA } from './fluxo';

const props = defineProps({ alvo: { type: String, default: 'lead' } });
const emit = defineEmits(['escolher', 'fechar']);
const { t } = useI18n();
const raiz = ref(null);
onClickOutside(raiz, () => emit('fechar'));

// B5: no Horário da conta só os passos que rodam sem lead (grupo vazio some)
const grupos = computed(() =>
  props.alvo === 'conta'
    ? PALETA.map(g => ({
        ...g,
        itens: g.itens.filter(i => PASSOS_CONTA.includes(i.tipo)),
      })).filter(g => g.itens.length)
    : PALETA
);

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
    <template v-for="grupo in grupos" :key="grupo.grupo">
      <h4
        class="mx-1.5 mb-1 mt-2.5 text-[11.5px] font-medium text-n-slate-10 first:mt-1"
      >
        {{ t(`CAPTAIN_RAMON.FLUXOS.GRUPOS.${grupo.grupo}`) }}
      </h4>
      <button
        v-for="item in grupo.itens"
        :key="item.chave"
        type="button"
        :data-testid="`paleta-${item.chave}`"
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
