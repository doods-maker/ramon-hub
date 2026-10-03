<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import PecaPainel from '../components/conteudo/PecaPainel.vue';

defineOptions({ name: 'RamonConteudo' });

const { t } = useI18n();

const COLUNAS = [
  { key: 'pauta', status: ['rascunho'] },
  { key: 'montando', status: ['aprovado', 'montando'] },
  { key: 'prontas', status: ['montado'] },
  { key: 'agendadas', status: ['agendado', 'publicando', 'falhou'] },
  { key: 'publicadas', status: ['publicado'] },
];

const pecas = ref([]);
const hasError = ref(false);
const aberta = ref(null);

const porColuna = computed(() =>
  COLUNAS.map(coluna => ({
    ...coluna,
    pecas: pecas.value.filter(p => coluna.status.includes(p.status)),
  }))
);

const carregar = async () => {
  hasError.value = false;
  try {
    const { data } = await RamonConteudoAPI.get();
    pecas.value = data.payload;
  } catch {
    hasError.value = true;
  }
};

const onChanged = () => carregar();

onMounted(carregar);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-hidden p-8">
    <RamonPageHeader :title="t('RAMON.CONTEUDO.TITLE')" />
    <p v-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('RAMON.CONTEUDO.LOAD_ERROR') }}
    </p>
    <div class="flex flex-1 gap-4 overflow-x-auto">
      <section
        v-for="coluna in porColuna"
        :key="coluna.key"
        :data-testid="`coluna-${coluna.key}`"
        class="flex w-64 shrink-0 flex-col gap-2 rounded-xl bg-n-alpha-1 p-3"
      >
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t(`RAMON.CONTEUDO.COLUNA.${coluna.key.toUpperCase()}`) }}
          <span class="text-n-slate-10">{{ coluna.pecas.length }}</span>
        </h2>
        <button
          v-for="peca in coluna.pecas"
          :key="peca.id"
          type="button"
          data-testid="peca-card"
          class="flex flex-col gap-1 rounded-lg bg-n-solid-1 p-2 text-left shadow-sm hover:bg-n-alpha-2"
          @click="aberta = peca.id"
        >
          <img
            v-if="peca.capa"
            :src="peca.capa"
            alt=""
            class="aspect-[4/5] w-full rounded object-cover"
          />
          <span class="text-sm text-n-slate-12">{{ peca.gancho }}</span>
          <span class="text-xs text-n-slate-10">
            {{ t(`RAMON.CONTEUDO.TIPO.${peca.tipo.toUpperCase()}`) }} ·
            {{ peca.tese }}
          </span>
          <span
            v-if="peca.travada"
            data-testid="peca-travada"
            class="text-xs text-n-amber-11"
          >
            {{ t('RAMON.CONTEUDO.TRAVADA') }}
          </span>
          <span v-if="peca.status === 'falhou'" class="text-xs text-n-ruby-11">
            {{ t('RAMON.CONTEUDO.FALHOU') }}
          </span>
        </button>
      </section>
    </div>
    <PecaPainel
      v-if="aberta"
      :peca-id="aberta"
      @changed="onChanged"
      @close="aberta = null"
    />
  </div>
</template>
