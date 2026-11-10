<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import { CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

// Tela Hoje (09/11/2026): as tarefas do ADVBOX de quem está logado.
// comAgenda (time advogados) = hoje + próximos 7 dias. As peças da esteira
// aparecem para quem tiver tarefa da esteira aberta (por ora, só o Eduardo) e
// somem quando a tarefa é concluída no ADVBOX.
const props = defineProps({ comAgenda: { type: Boolean, default: false } });
const { t } = useI18n();

const dados = ref({ hoje: [], semana: [], esteira: [] });
const advboxFora = ref(false);

const porDia = computed(() =>
  dados.value.semana.reduce((dias, item) => {
    (dias[item.data] ||= []).push(item);
    return dias;
  }, {})
);

// Meio-dia: a data do ADVBOX não tem fuso; evita cair no dia anterior.
const diaCurto = data =>
  new Date(`${data}T12:00:00`).toLocaleDateString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  });

// ponytail: busca pelo nome do arquivo no Drive de quem abre (sem chamada à
// API); se a advogada não tiver acesso à pasta, a busca volta vazia.
const linkDrive = peca =>
  `https://drive.google.com/drive/search?q=${encodeURIComponent(peca)}`;

onMounted(async () => {
  try {
    const { data } = await ChegadasAPI.meuDia();
    dados.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
});
</script>

<template>
  <section
    v-if="dados.esteira.length"
    data-testid="meu-dia-esteira-bloco"
    class="flex flex-col gap-2.5"
  >
    <h2 :class="TITULO">{{ t('RAMON.MEU_DIA.ESTEIRA') }}</h2>
    <div :class="CARTAO" class="flex flex-col gap-1">
      <div
        v-for="item in dados.esteira"
        :key="item.advbox_post_id"
        data-testid="meu-dia-esteira"
        class="flex items-center gap-3 rounded-lg px-2 py-2"
      >
        <div class="min-w-0 flex-1">
          <p class="truncate text-[13.5px] font-medium text-n-slate-12">
            {{ item.cliente_nome }}
          </p>
          <p class="truncate text-[11px] text-n-slate-10">
            {{ item.situacao }}
          </p>
        </div>
        <a
          v-if="item.peca"
          :href="linkDrive(item.peca)"
          target="_blank"
          rel="noopener noreferrer"
          :title="item.peca"
          :class="[CHIP, TOM.teal]"
        >
          {{ t('RAMON.MEU_DIA.PECA_PRONTA') }}
        </a>
        <span v-else :class="[CHIP, TOM.amber]">
          {{ t('RAMON.MEU_DIA.PAROU') }}
        </span>
      </div>
    </div>
  </section>

  <section
    v-if="props.comAgenda"
    data-testid="meu-dia-agenda"
    class="flex flex-col gap-2.5"
  >
    <h2 :class="TITULO">{{ t('RAMON.MEU_DIA.HOJE') }}</h2>
    <div :class="CARTAO" class="flex flex-col gap-1">
      <p
        v-if="advboxFora"
        data-testid="meu-dia-fora"
        class="text-sm text-n-ruby-11"
      >
        {{ t('RAMON.MEU_DIA.ADVBOX_FORA') }}
      </p>
      <p v-else-if="!dados.hoje.length" class="text-xs text-n-slate-10">
        {{ t('RAMON.MEU_DIA.SEM_HOJE') }}
      </p>
      <div
        v-for="item in dados.hoje"
        :key="item.advbox_post_id"
        data-testid="meu-dia-hoje"
        class="flex items-center gap-3 rounded-lg px-2 py-2"
        :class="{ 'line-through opacity-60': item.concluida }"
      >
        <div class="min-w-0 flex-1">
          <p class="truncate text-[13.5px] font-medium text-n-slate-12">
            {{ item.tarefa }}
          </p>
          <p class="truncate text-[11px] text-n-slate-10">
            {{ [item.cliente_nome, item.local].filter(Boolean).join(' · ') }}
          </p>
        </div>
        <span
          v-if="item.prazo"
          data-testid="meu-dia-prazo"
          :class="[CHIP, TOM.amber]"
        >
          {{ t('RAMON.MEU_DIA.PRAZO', { dia: diaCurto(item.prazo) }) }}
        </span>
      </div>
    </div>

    <h2 :class="TITULO" class="mt-2.5">{{ t('RAMON.MEU_DIA.SEMANA') }}</h2>
    <div :class="CARTAO" class="flex flex-col gap-3">
      <p v-if="!dados.semana.length" class="text-xs text-n-slate-10">
        {{ t('RAMON.MEU_DIA.SEM_SEMANA') }}
      </p>
      <div
        v-for="(itens, data) in porDia"
        :key="data"
        data-testid="meu-dia-dia"
        class="flex flex-col gap-1"
      >
        <p class="font-mono text-[11px] text-n-slate-10">
          {{ diaCurto(data) }}
        </p>
        <p
          v-for="item in itens"
          :key="item.advbox_post_id"
          data-testid="meu-dia-semana"
          class="truncate text-[13px] text-n-slate-12"
        >
          {{ item.tarefa }}
          <span class="text-n-slate-10">{{ `· ${item.cliente_nome}` }}</span>
        </p>
      </div>
    </div>
  </section>
</template>
