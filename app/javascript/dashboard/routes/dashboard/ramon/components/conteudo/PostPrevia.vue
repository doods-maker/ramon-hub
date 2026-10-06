<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  imagens: { type: Array, required: true },
  legenda: { type: String, default: '' },
});

const CONTA = 'ramonantonioadvogados'; // handle fixo da banca
const SIGLA = 'RA';
const CORTE = 125; // ponytail: corte aproximado do "mais" no feed do app; ajustar se destoar
const { t } = useI18n();
const indice = ref(0);
const expandida = ref(false);

const cortada = computed(
  () => !expandida.value && props.legenda.length > CORTE
);
const textoLegenda = computed(() =>
  cortada.value ? `${props.legenda.slice(0, CORTE)}…` : props.legenda
);

watch(
  () => props.imagens,
  () => {
    indice.value = 0;
  }
);
</script>

<template>
  <article
    class="mx-auto w-full max-w-sm overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 text-n-slate-12"
  >
    <header class="flex items-center gap-2 p-3">
      <span
        class="flex size-8 items-center justify-center rounded-full bg-n-slate-12 text-xs font-semibold text-n-solid-1"
      >
        {{ SIGLA }}
      </span>
      <span class="text-sm font-semibold">{{ CONTA }}</span>
    </header>
    <div class="relative aspect-[4/5] bg-n-alpha-2">
      <a :href="imagens[indice]" target="_blank" rel="noopener noreferrer">
        <img
          data-testid="slide"
          :src="imagens[indice]"
          alt=""
          class="size-full object-cover"
        />
      </a>
      <button
        v-if="indice > 0"
        data-testid="anterior"
        type="button"
        class="absolute left-2 top-1/2 flex size-7 -translate-y-1/2 items-center justify-center rounded-full bg-n-solid-1/80 p-0 text-n-slate-12 shadow"
        @click="indice -= 1"
      >
        <span class="i-lucide-chevron-left" />
      </button>
      <button
        v-if="indice < imagens.length - 1"
        data-testid="proximo"
        type="button"
        class="absolute right-2 top-1/2 flex size-7 -translate-y-1/2 items-center justify-center rounded-full bg-n-solid-1/80 p-0 text-n-slate-12 shadow"
        @click="indice += 1"
      >
        <span class="i-lucide-chevron-right" />
      </button>
    </div>
    <div v-if="imagens.length > 1" class="flex justify-center gap-1 py-2">
      <span
        v-for="(_, i) in imagens"
        :key="i"
        data-testid="bolinha"
        class="size-1.5 rounded-full"
        :class="i === indice ? 'bg-n-blue-9' : 'bg-n-slate-6'"
      />
    </div>
    <p class="whitespace-pre-line px-3 pb-3 text-sm" data-testid="legenda">
      <span class="font-semibold">{{ CONTA }}</span>
      {{ textoLegenda }}
      <button
        v-if="cortada"
        data-testid="legenda-mais"
        type="button"
        class="p-0 text-n-slate-10"
        @click="expandida = true"
      >
        {{ t('RAMON.CONTEUDO.MAIS') }}
      </button>
    </p>
  </article>
</template>
