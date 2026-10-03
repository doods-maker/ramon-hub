<script setup>
import { computed, onMounted, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import RamonHojeAPI from 'dashboard/api/ramonHoje';
import HojeGestor from '../components/hoje/HojeGestor.vue';
import HojeComercial from '../components/hoje/HojeComercial.vue';
import HojeRecepcao from '../components/hoje/HojeRecepcao.vue';
import HojeAdvogada from '../components/hoje/HojeAdvogada.vue';

// Tela Hoje (redesign v2, Onda 3): "o que eu faço agora?" por papel.
// O papel vem do backend (ramon_hoje); aqui só se escolhe o desenho.
const { t } = useI18n();
const dados = ref(null);
const erro = ref(false);

const POR_PAPEL = {
  gestor: HojeGestor,
  recepcao: HojeRecepcao,
  advogada: HojeAdvogada,
};
const componente = computed(
  () => POR_PAPEL[dados.value?.papel] || HojeComercial
);
// "sexta, 3 de outubro" (mockup) — meio-dia evita virar o dia no fuso.
const dataLonga = computed(() =>
  dados.value
    ? new Date(`${dados.value.data}T12:00:00`)
        .toLocaleDateString('pt-BR', {
          weekday: 'long',
          day: 'numeric',
          month: 'long',
        })
        .replace('-feira', '')
    : ''
);

const carregar = async () => {
  try {
    const { data } = await RamonHojeAPI.get();
    dados.value = data;
    erro.value = false;
  } catch {
    erro.value = true;
  }
};

onMounted(carregar);
useIntervalFn(carregar, 60 * 1000);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto bg-n-background">
    <div
      class="flex h-14 flex-shrink-0 items-center gap-2.5 border-b border-n-weak px-7"
    >
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t('RAMON.HOJE.TITULO') }}
      </h1>
      <span class="text-[13px] text-n-slate-9">{{ dataLonga }}</span>
    </div>
    <div
      v-if="erro && !dados"
      data-testid="hoje-erro"
      class="p-7 text-[13px] text-n-slate-11"
    >
      {{ t('RAMON.HOJE.ERRO') }}
      <button class="ml-2 text-n-blue-11 underline" @click="carregar">
        {{ t('RAMON.HOJE.TENTAR') }}
      </button>
    </div>
    <component
      :is="componente"
      v-else-if="dados"
      :dados="dados"
      @recarregar="carregar"
    />
  </div>
</template>
