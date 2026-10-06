<script setup>
// Painel do time (operação comercial, doc 04 §3–§4): KPIs do SDR e do Closer
// contra as metas do plano. Gestor vê o time todo, cada pessoa e a tabela por
// pessoa; SDR/Closer veem só os próprios números (o backend filtra).
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import RamonPainelTimeAPI from 'dashboard/api/ramonPainelTime';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  TITULO,
  TOM,
} from '../helpers/ui';
import { COR_STATUS, formatarKpi, statusKpi } from '../helpers/painelTime';

defineOptions({ name: 'RamonPainelTime' });

const PAPEIS = ['sdr', 'closer'];
const PERIODOS = ['hoje', 'semana', 'mes', 'mes_passado'];
// Blocos de cartões por papel (ordem do mockup aprovado 06/10).
const BLOCOS = {
  sdr: [
    {
      titulo: 'VELOCIDADE',
      kpis: ['primeira_resposta', 'sem_resposta', 'registro_completo'],
    },
    {
      titulo: 'QUALIDADE',
      kpis: ['qualificado_agendada', 'show', 'nao_qualificada'],
    },
  ],
  closer: [
    {
      titulo: 'FECHAMENTO',
      kpis: ['conversao', 'assinado_na_reuniao', 'vou_pensar_48h'],
    },
    {
      titulo: 'POS_FECHAMENTO',
      kpis: ['docs_7d', 'cancelamento_7d', 'painel', 'dossie_24h'],
    },
  ],
};
// Colunas da tabela por pessoa (só o gestor vê).
const COLUNAS = {
  sdr: ['primeira_resposta', 'sem_resposta', 'show', 'nao_qualificada'],
  closer: [
    'conversao',
    'assinado_na_reuniao',
    'docs_7d',
    'cancelamento_7d',
    'painel',
  ],
};
const COR_TEXTO = {
  atencao: 'text-n-amber-11',
  cobrar: 'text-n-ruby-11',
};

const { t } = useI18n();
const store = useStore();
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);

const papel = ref('sdr');
const periodo = ref('mes');
// 'time' ou o id da pessoa escolhida (só o gestor escolhe)
const alvo = ref('time');
const dados = ref(null);
const loading = ref(true);
const error = ref(false);

const pessoas = computed(() => dados.value?.pessoas ?? []);
const metas = computed(() => dados.value?.metas ?? {});
// Linha em foco: o time (gestor), a pessoa escolhida, ou a própria (agente).
const linha = computed(() => {
  if (!dados.value) return null;
  if (!dados.value.time) return pessoas.value[0] ?? null;
  if (alvo.value === 'time') return dados.value.time;
  return pessoas.value.find(p => p.user.id === alvo.value) ?? dados.value.time;
});
const vazio = computed(() => !pessoas.value.length);

// Agente abre no SDR; se não está no time SDR, vai uma vez pro Closer.
let foiProCloser = false;
const carregar = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonPainelTimeAPI.get({
      papel: papel.value,
      periodo: periodo.value,
    });
    dados.value = data;
    if (!isAdmin.value && !data.pessoas.length && !foiProCloser) {
      foiProCloser = true;
      if (papel.value === 'sdr') papel.value = 'closer';
    }
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

const trocarPapel = valor => {
  papel.value = valor;
  alvo.value = 'time';
};

// ----- cartões
const statusDe = (chave, kpi) => statusKpi(kpi?.valor, metas.value[chave]);
const filete = status => (status ? FILETE[COR_STATUS[status]] : '');
const alvoTexto = chave => {
  const meta = metas.value[chave];
  if (!meta) return '';
  if (meta.alvo === 0) return t('RAMON.PAINEL_TIME.ALVO.ZERO');
  return t(`RAMON.PAINEL_TIME.ALVO.${meta.sentido}`, {
    alvo: formatarKpi(meta.alvo, meta.unidade),
  });
};
const detalhe = kpi => {
  if (!kpi || !kpi.num) return '';
  if (kpi.den == null)
    return t('RAMON.PAINEL_TIME.RESPOSTAS', { n: kpi.num }, kpi.num);
  return t('RAMON.PAINEL_TIME.DE', { num: kpi.num, den: kpi.den });
};
const valorDe = (chave, kpi) =>
  formatarKpi(kpi?.valor, metas.value[chave]?.unidade);

const cartoes = computed(() =>
  BLOCOS[papel.value].map(bloco => ({
    titulo: bloco.titulo,
    itens: bloco.kpis.map(chave => {
      const kpi = linha.value?.kpis?.[chave];
      const status = statusDe(chave, kpi);
      return {
        chave,
        valor: valorDe(chave, kpi),
        alvo: alvoTexto(chave),
        detalhe: detalhe(kpi),
        status,
      };
    }),
  }))
);

// ----- meta do mês
const metaMes = computed(() => linha.value?.meta_mes ?? null);
const metaPct = computed(() => {
  const m = metaMes.value;
  if (!m?.meta) return 0;
  return Math.min(100, Math.round((m.realizado / m.meta) * 100));
});
const metaLinha = computed(() => {
  const m = metaMes.value;
  if (!m?.meta) return t('RAMON.PAINEL_TIME.META.SEM_META');
  const faltam = m.meta - m.realizado;
  if (faltam <= 0) return t('RAMON.PAINEL_TIME.META.BATIDA');
  if (!m.dias_uteis_restantes) return `${metaPct.value}%`;
  const ritmo = (faltam / m.dias_uteis_restantes).toLocaleString('pt-BR', {
    maximumFractionDigits: 1,
  });
  return `${metaPct.value}% · ${t('RAMON.PAINEL_TIME.META.FALTAM', {
    n: faltam,
    dias: m.dias_uteis_restantes,
    ritmo,
  })}`;
});

// ----- volume
const serie = computed(() => linha.value?.volume?.serie ?? []);
const maxSerie = computed(() => Math.max(1, ...serie.value.map(p => p.n)));
const alturaBarra = n =>
  `${Math.max(4, Math.round((n / maxSerie.value) * 100))}%`;
// média por dia útil já corrido (SDR): só os dias seg–sex até hoje.
const mediaDiaUtil = computed(() => {
  const hoje = new Date().toISOString().slice(0, 10);
  const dias = serie.value.filter(p => {
    const dia = new Date(`${p.inicio}T12:00:00`).getDay();
    return p.inicio <= hoje && dia !== 0 && dia !== 6;
  });
  if (!dias.length) return null;
  const total = dias.reduce((soma, p) => soma + p.n, 0);
  return (total / dias.length).toLocaleString('pt-BR', {
    maximumFractionDigits: 1,
  });
});

const volumeLinha = computed(() => {
  const total = t('RAMON.PAINEL_TIME.VOLUME.TOTAL', {
    n: linha.value?.volume?.total ?? 0,
  });
  if (papel.value !== 'sdr' || !mediaDiaUtil.value) return total;
  const media = t('RAMON.PAINEL_TIME.VOLUME.MEDIA', {
    media: mediaDiaUtil.value,
  });
  return `${total} · ${media}`;
});

// ----- tabela por pessoa
const celula = (pessoa, chave) => {
  const kpi = pessoa.kpis[chave];
  return {
    texto: valorDe(chave, kpi),
    cor: COR_TEXTO[statusDe(chave, kpi)] ?? 'text-n-slate-12',
  };
};

const segmento = ativo => [
  CHIP,
  ativo ? TOM.blue : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
];

watch([papel, periodo], carregar);
onMounted(carregar);
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.PAINEL_TIME.TITLE')"
        :subtitle="t('RAMON.PAINEL_TIME.SUBTITLE')"
        compact
      />

      <div class="flex flex-wrap items-center gap-2">
        <div
          class="flex items-center gap-0.5 rounded-lg border border-n-weak p-0.5"
        >
          <button
            v-for="p in PAPEIS"
            :key="p"
            type="button"
            :data-testid="`painel-papel-${p}`"
            :class="segmento(papel === p)"
            @click="trocarPapel(p)"
          >
            {{ t(`RAMON.PAINEL_TIME.PAPEL.${p}`) }}
          </button>
        </div>
        <div
          class="flex items-center gap-0.5 rounded-lg border border-n-weak p-0.5"
        >
          <button
            v-for="p in PERIODOS"
            :key="p"
            type="button"
            :data-testid="`painel-periodo-${p}`"
            :class="segmento(periodo === p)"
            @click="periodo = p"
          >
            {{ t(`RAMON.PAINEL_TIME.PERIODO.${p}`) }}
          </button>
        </div>
        <div
          v-if="isAdmin && pessoas.length"
          data-testid="painel-alvo"
          class="flex flex-wrap items-center gap-0.5 rounded-lg border border-n-weak p-0.5"
        >
          <button
            type="button"
            data-testid="painel-alvo-time"
            :class="segmento(alvo === 'time')"
            @click="alvo = 'time'"
          >
            {{ t('RAMON.PAINEL_TIME.TIME_TODO') }}
          </button>
          <button
            v-for="pessoa in pessoas"
            :key="pessoa.user.id"
            type="button"
            data-testid="painel-alvo-pessoa"
            :class="segmento(alvo === pessoa.user.id)"
            @click="alvo = pessoa.user.id"
          >
            {{ pessoa.user.name }}
          </button>
        </div>
      </div>

      <div
        v-if="loading && !dados"
        class="h-32 animate-pulse rounded-xl bg-n-alpha-2"
      />
      <div v-else-if="error" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11">
          {{ t('RAMON.PAINEL_TIME.LOAD_ERROR') }}
        </p>
        <Button
          link
          xs
          :label="t('RAMON.PAINEL_TIME.RETRY')"
          @click="carregar"
        />
      </div>
      <p
        v-else-if="vazio"
        data-testid="painel-vazio"
        class="m-0 text-sm text-n-slate-10"
      >
        {{
          t(
            isAdmin
              ? 'RAMON.PAINEL_TIME.VAZIO'
              : 'RAMON.PAINEL_TIME.VAZIO_AGENTE',
            { papel: t(`RAMON.PAINEL_TIME.PAPEL.${papel}`) }
          )
        }}
      </p>
      <template v-else-if="linha">
        <section class="flex flex-col gap-2">
          <h2 class="m-0" :class="TITULO">
            {{ t('RAMON.PAINEL_TIME.BLOCO.META') }}
          </h2>
          <div data-testid="painel-meta" :class="CARTAO" class="max-w-xl !px-4">
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`RAMON.PAINEL_TIME.META.${papel}`) }}
            </p>
            <p
              class="m-0 mt-0.5 font-mono text-[26px] font-medium tabular-nums text-n-slate-12"
            >
              {{ metaMes.realizado }}
              <span v-if="metaMes.meta" class="text-[15px] text-n-slate-10">
                {{ `/ ${metaMes.meta}` }}
              </span>
            </p>
            <span
              class="mt-2 block h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
            >
              <span
                class="block h-full rounded-full bg-n-blue-9"
                :style="{ width: `${metaPct}%` }"
              />
            </span>
            <p class="m-0 mt-1.5 text-[11.5px] text-n-slate-10">
              {{ metaLinha }}
            </p>
            <p
              v-if="metaMes.aguardando"
              data-testid="painel-aguardando"
              class="m-0 text-[11.5px] text-n-slate-10"
            >
              {{
                t('RAMON.PAINEL_TIME.META.AGUARDANDO', {
                  n: metaMes.aguardando,
                })
              }}
            </p>
          </div>
        </section>

        <section
          v-for="bloco in cartoes"
          :key="bloco.titulo"
          class="flex flex-col gap-2"
        >
          <h2 class="m-0" :class="TITULO">
            {{ t(`RAMON.PAINEL_TIME.BLOCO.${bloco.titulo}`) }}
          </h2>
          <div
            class="grid gap-2.5 grid-cols-[repeat(auto-fill,minmax(210px,1fr))]"
          >
            <div
              v-for="item in bloco.itens"
              :key="item.chave"
              :data-testid="`painel-kpi-${item.chave}`"
              :data-status="item.status || 'sem_dado'"
              :class="[
                item.status ? CARTAO_STATUS : CARTAO,
                filete(item.status),
              ]"
              class="!px-3.5"
            >
              <p class="m-0 text-xs text-n-slate-11">
                {{ t(`RAMON.PAINEL_TIME.KPI.${item.chave}`) }}
              </p>
              <p
                class="m-0 mt-0.5 font-mono text-[26px] font-medium tabular-nums text-n-slate-12"
              >
                {{ item.valor }}
              </p>
              <p
                class="m-0 flex flex-wrap items-center gap-1.5 text-[11.5px] text-n-slate-10"
              >
                <span>{{ item.alvo }}</span>
                <span v-if="item.detalhe" class="font-mono tabular-nums">
                  {{ `· ${item.detalhe}` }}
                </span>
                <span
                  :class="[
                    CHIP,
                    item.status ? TOM[COR_STATUS[item.status]] : TOM.slate,
                  ]"
                >
                  {{
                    item.status
                      ? t(`RAMON.PAINEL_TIME.STATUS.${item.status}`)
                      : t('RAMON.PAINEL_TIME.STATUS.SEM_DADO')
                  }}
                </span>
              </p>
            </div>
          </div>
        </section>

        <section class="flex flex-col gap-2">
          <h2 class="m-0" :class="TITULO">
            {{ t('RAMON.PAINEL_TIME.BLOCO.VOLUME') }}
          </h2>
          <div
            data-testid="painel-volume"
            :class="CARTAO"
            class="max-w-xl !px-4"
          >
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`RAMON.PAINEL_TIME.VOLUME.${papel}`) }}
            </p>
            <div class="mt-1.5 flex h-11 items-end gap-[3px]">
              <span
                v-for="ponto in serie"
                :key="ponto.inicio"
                class="block flex-1 rounded-sm bg-n-blue-9/35"
                :title="`${ponto.inicio}: ${ponto.n}`"
                :style="{ height: alturaBarra(ponto.n) }"
              />
            </div>
            <p
              data-testid="painel-volume-total"
              class="m-0 mt-1.5 font-mono text-[11.5px] tabular-nums text-n-slate-10"
            >
              {{ volumeLinha }}
            </p>
          </div>
        </section>

        <section
          v-if="dados.time"
          data-testid="painel-tabela"
          class="flex flex-col gap-2"
        >
          <h2 class="m-0" :class="TITULO">
            {{ t('RAMON.PAINEL_TIME.BLOCO.POR_PESSOA') }}
          </h2>
          <div :class="CARTAO" class="overflow-x-auto !p-0">
            <table class="w-full text-[13px]">
              <thead>
                <tr>
                  <th class="px-3 py-2 text-left" :class="TITULO">
                    {{ t(`RAMON.PAINEL_TIME.PAPEL.${papel}`) }}
                  </th>
                  <th class="px-3 py-2 text-right" :class="TITULO">
                    {{ t('RAMON.PAINEL_TIME.COLUNA.META') }}
                  </th>
                  <th
                    v-for="chave in COLUNAS[papel]"
                    :key="chave"
                    class="px-3 py-2 text-right"
                    :class="TITULO"
                  >
                    {{ t(`RAMON.PAINEL_TIME.COLUNA.${chave}`) }}
                  </th>
                  <th class="px-3 py-2 text-right" :class="TITULO">
                    {{
                      t(
                        papel === 'sdr'
                          ? 'RAMON.PAINEL_TIME.COLUNA.LEADS'
                          : 'RAMON.PAINEL_TIME.COLUNA.CONTRATOS'
                      )
                    }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="pessoa in pessoas"
                  :key="pessoa.user.id"
                  data-testid="painel-linha-pessoa"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2 text-n-slate-12">
                    {{ pessoa.user.name }}
                  </td>
                  <td
                    class="px-3 py-2 text-right font-mono tabular-nums text-n-slate-12"
                  >
                    {{ pessoa.meta_mes.realizado }}
                    {{ `/ ${pessoa.meta_mes.meta ?? '—'}` }}
                  </td>
                  <td
                    v-for="chave in COLUNAS[papel]"
                    :key="chave"
                    class="px-3 py-2 text-right font-mono tabular-nums"
                    :class="celula(pessoa, chave).cor"
                  >
                    {{ celula(pessoa, chave).texto }}
                  </td>
                  <td
                    class="px-3 py-2 text-right font-mono tabular-nums text-n-slate-12"
                  >
                    {{ pessoa.volume.total }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <p :class="[AVISO, TOM.blue]" class="m-0">
          {{ t('RAMON.PAINEL_TIME.NOTA') }}
        </p>
      </template>
    </div>
  </div>
</template>
