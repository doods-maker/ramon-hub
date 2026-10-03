<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import AlertaCaixa from './AlertaCaixa.vue';
import HojeBloco from './HojeBloco.vue';
import HojeMetrica from './HojeMetrica.vue';
import { GRADE, CAIXA, CAIXA_TITULO, juntar } from './hoje';

// Tela Hoje do gestor: o que precisa dele, o time no dia, o mês e o funil agora.
const props = defineProps({ dados: { type: Object, required: true } });

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const ALERTA = {
  sla: { icone: 'i-lucide-clock', rota: 'ramon_esteira', acao: 'VER_FILA' },
  parado: {
    icone: 'i-lucide-hourglass',
    rota: 'ramon_funil',
    acao: 'ABRIR_FUNIL',
  },
  docs: {
    icone: 'i-lucide-file-warning',
    rota: 'ramon_pos_venda',
    acao: 'VER_POS_VENDA',
  },
  conteudo: {
    icone: 'i-lucide-image',
    rota: 'ramon_conteudo',
    acao: 'REVISAR',
  },
};

const textoDo = a => {
  if (a.tipo === 'sla')
    return t('RAMON.HOJE.ALERTA.SLA_TEXTO', { nomes: juntar(a.nomes) });
  if (a.tipo === 'parado')
    return t('RAMON.HOJE.ALERTA.PARADO_TEXTO', {
      count: a.count,
      dias: a.dias,
    });
  if (a.tipo === 'docs') return t('RAMON.HOJE.ALERTA.DOCS_TEXTO');
  return `${juntar(a.nomes.map(n => `“${n}”`))}.`;
};

const alertas = computed(() =>
  props.dados.precisa.map(a => ({
    key: a.tipo,
    nivel: a.nivel,
    icone: ALERTA[a.tipo].icone,
    titulo: t(`RAMON.HOJE.ALERTA.${a.tipo.toUpperCase()}_TITULO`, {
      count: a.count,
      etapa: a.etapa,
    }),
    texto: textoDo(a),
    acao: {
      label: t(`RAMON.HOJE.ALERTA.${ALERTA[a.tipo].acao}`),
      to: accountScopedRoute(ALERTA[a.tipo].rota),
    },
  }))
);

const time = computed(() => props.dados.time);
const mes = computed(() => props.dados.mes);
// 3.67 min → "3m40s"
const tempoMedio = computed(() => {
  const minutos = time.value.sdr.media_minutos;
  if (minutos == null) return '—';
  const s = Math.round(minutos * 60);
  return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s`;
});
const nomeDoMes = computed(() => {
  const nome = new Date(`${props.dados.data}T12:00:00`).toLocaleDateString(
    'pt-BR',
    { month: 'long' }
  );
  return nome.charAt(0).toUpperCase() + nome.slice(1);
});

const CARTAO = 'rounded-[10px] border border-n-weak px-3.5 py-3';
const CARTAO_TITULO = 'mb-1.5 block text-[13px] font-medium text-n-slate-12';
const CARTAO_LINHA = 'block text-[12.5px] text-n-slate-11';
const NUM = 'font-mono text-n-slate-12';
</script>

<template>
  <div :class="GRADE">
    <div class="min-w-0">
      <HojeBloco
        :titulo="t('RAMON.HOJE.PRECISA')"
        :total="dados.precisa.length"
        :vazio="t('RAMON.HOJE.PRECISA_VAZIO')"
        :fila="false"
      >
        <AlertaCaixa
          v-for="a in alertas"
          :key="a.key"
          :nivel="a.nivel"
          :icone="a.icone"
          :titulo="a.titulo"
          :texto="a.texto"
          :acao="a.acao"
        />
      </HojeBloco>

      <section class="mb-8">
        <h2 class="mb-1 text-[14.5px] font-semibold text-n-slate-12">
          {{ t('RAMON.HOJE.TIME') }}
        </h2>
        <div class="grid grid-cols-3 gap-3">
          <div :class="CARTAO">
            <b :class="CARTAO_TITULO">{{ t('RAMON.HOJE.PAPEL_SDR') }}</b>
            <span :class="CARTAO_LINHA">
              <span :class="NUM">{{ time.sdr.respondidos }}</span>
              {{ t('RAMON.HOJE.RESPONDIDOS', { count: time.sdr.respondidos }) }}
            </span>
            <span :class="CARTAO_LINHA">
              {{ t('RAMON.HOJE.TEMPO_MEDIO') }}
              <span :class="NUM">{{ tempoMedio }}</span>
            </span>
          </div>
          <div :class="CARTAO">
            <b :class="CARTAO_TITULO">{{ t('RAMON.HOJE.PAPEL_CLOSER') }}</b>
            <span :class="CARTAO_LINHA">
              <span :class="NUM">{{ time.closer.reunioes }}</span>
              {{ t('RAMON.HOJE.REUNIOES', { count: time.closer.reunioes }) }}
            </span>
            <span :class="CARTAO_LINHA">
              <span :class="NUM">{{ time.closer.contratos }}</span>
              {{
                t('RAMON.HOJE.CONTRATOS_ASSINADOS', {
                  count: time.closer.contratos,
                })
              }}
            </span>
          </div>
          <div :class="CARTAO">
            <b :class="CARTAO_TITULO">{{ t('RAMON.HOJE.PAPEL_RECEPCAO') }}</b>
            <span :class="CARTAO_LINHA">
              <span :class="NUM">{{ time.recepcao.atribuidas }}</span>
              {{
                t('RAMON.HOJE.ATRIBUIDAS_HOJE', {
                  count: time.recepcao.atribuidas,
                })
              }}
            </span>
            <span :class="CARTAO_LINHA">
              <span :class="NUM">{{ time.recepcao.chegadas }}</span>
              {{ t('RAMON.HOJE.CHEGADAS', { count: time.recepcao.chegadas }) }}
            </span>
          </div>
        </div>
      </section>
    </div>

    <aside>
      <div :class="CAIXA">
        <h3 :class="CAIXA_TITULO">{{ nomeDoMes }}</h3>
        <HojeMetrica
          :rotulo="t('RAMON.HOJE.CONTRATOS')"
          :valor="mes.contratos"
          :meta="mes.meta_contratos"
          barra="act"
        />
        <HojeMetrica
          :rotulo="t('RAMON.HOJE.REUNIOES_QUALIFICADAS')"
          :valor="mes.reunioes_qualificadas"
        />
        <HojeMetrica
          :rotulo="t('RAMON.HOJE.DOCS_COMPLETOS')"
          :valor="mes.docs_completos"
          :meta="mes.ganhos_mes || null"
          barra="ok"
        />
      </div>
      <div :class="CAIXA">
        <h3 :class="CAIXA_TITULO">{{ t('RAMON.HOJE.FUNIL_AGORA') }}</h3>
        <div
          v-for="e in dados.funil"
          :key="e.etapa"
          class="flex items-center border-b border-n-weak px-1 py-2"
        >
          <span
            class="ramon-stage-pill inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-[9px] py-1 text-[11.5px] font-medium leading-none"
            :style="{ '--stage': e.cor || DEFAULT_STAGE_COLOR }"
          >
            <span class="size-1.5 rounded-full bg-current" />
            {{ e.etapa }}
          </span>
          <span class="ml-auto font-mono text-[12.5px] text-n-slate-12">
            {{ e.count }}
          </span>
        </div>
      </div>
    </aside>
  </div>
</template>
