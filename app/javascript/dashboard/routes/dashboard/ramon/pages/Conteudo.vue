<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import PecaPainel from '../components/conteudo/PecaPainel.vue';
import { AVISO, CARTAO, CHIP, TOM } from '../helpers/ui';

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
// Token do IG ausente: aviso no topo e agendar/publicar bloqueados no painel.
const tokenIg = ref(true);
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
    tokenIg.value = data.token_ig !== false;
  } catch {
    hasError.value = true;
  }
};

const onChanged = () => carregar();

onMounted(carregar);
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-hidden bg-n-background p-4 sm:p-8"
  >
    <!-- coluna centrada do tamanho do quadro (5 raias) -->
    <div class="mx-auto flex min-h-0 w-full max-w-max flex-1 flex-col gap-4">
      <RamonPageHeader class="!mb-0" :title="t('RAMON.CONTEUDO.TITLE')" />
      <p v-if="hasError" :class="[AVISO, TOM.ruby]" class="self-start">
        {{ t('RAMON.CONTEUDO.LOAD_ERROR') }}
      </p>
      <p
        v-if="!tokenIg"
        data-testid="sem-token"
        :class="[AVISO, TOM.amber]"
        class="self-start"
      >
        {{ t('RAMON.CONTEUDO.SEM_TOKEN') }}
      </p>
      <div class="flex min-h-0 flex-1 gap-4 overflow-x-auto">
        <section
          v-for="coluna in porColuna"
          :key="coluna.key"
          :data-testid="`coluna-${coluna.key}`"
          class="ramon-column flex w-64 shrink-0 flex-col gap-2 overflow-y-auto rounded-xl border border-n-weak p-2.5"
        >
          <h2
            class="flex items-baseline gap-2 px-1 pb-1 text-sm font-medium text-n-slate-12"
          >
            {{ t(`RAMON.CONTEUDO.COLUNA.${coluna.key.toUpperCase()}`) }}
            <span class="font-mono text-xs tabular-nums text-n-slate-10">
              {{ coluna.pecas.length }}
            </span>
          </h2>
          <button
            v-for="peca in coluna.pecas"
            :key="peca.id"
            type="button"
            data-testid="peca-card"
            :class="CARTAO"
            class="flex flex-col gap-1.5 border-solid text-left hover:border-n-strong"
            @click="aberta = peca.id"
          >
            <img
              v-if="peca.capa"
              :src="peca.capa"
              alt=""
              class="aspect-[4/5] w-full rounded-lg object-cover"
            />
            <span class="text-sm text-n-slate-12">{{ peca.gancho }}</span>
            <span class="text-xs text-n-slate-10">
              {{ t(`RAMON.CONTEUDO.TIPO.${peca.tipo.toUpperCase()}`) }} ·
              {{ peca.tese }}
            </span>
            <span
              v-if="peca.travada"
              data-testid="peca-travada"
              :class="[AVISO, TOM.amber]"
              class="!px-2 !py-1"
            >
              {{ t('RAMON.CONTEUDO.TRAVADA') }}
            </span>
            <span
              v-if="peca.status === 'falhou' || peca.erro"
              :class="[CHIP, TOM.ruby]"
              class="self-start"
            >
              {{
                peca.status === 'falhou'
                  ? t('RAMON.CONTEUDO.FALHOU')
                  : t('RAMON.CONTEUDO.COM_ERRO')
              }}
            </span>
          </button>
        </section>
      </div>
    </div>
    <PecaPainel
      v-if="aberta"
      :peca-id="aberta"
      :token-ig="tokenIg"
      @changed="onChanged"
      @close="aberta = null"
    />
  </div>
</template>
