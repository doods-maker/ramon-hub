<script setup>
// Um processo da Conferência de fases: etapa do ADVBOX ao lado da fase do
// Painel do Cliente, o que decidiu a fase e a marcação da equipe. Cada
// mudança sobe como `salvar` (só o campo mexido) — quem grava é a página.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  TITULO,
  TOM,
} from '../../helpers/ui';
import {
  TOM_DO_GRUPO,
  dataBr,
  diaMesHora,
} from '../../helpers/conferenciaFases';

const props = defineProps({
  linha: { type: Object, required: true },
});
const emit = defineEmits(['salvar']);

const { t } = useI18n();
const MARCAS = { certo: 'teal', errado: 'ruby' };

const lados = computed(() => [
  {
    chave: 'ADVBOX',
    etapa: props.linha.etapa_advbox,
    fase: props.linha.fase_advbox,
  },
  {
    chave: 'PAINEL',
    etapa: props.linha.painel_titulo,
    fase: props.linha.fase_painel,
  },
]);

// O que decidiu a fase do painel: o tribunal, a agenda ou só o nº do processo.
const decidiu = computed(() => {
  const { tribunal, agenda, ultimo_andamento: ultimo } = props.linha;
  let texto = t('RAMON.CONFERENCIA.SEM_ANDAMENTO');
  if (tribunal) {
    texto = t('RAMON.CONFERENCIA.DECIDIU_TRIBUNAL', {
      titulo: tribunal.titulo,
      data: dataBr(tribunal.data),
    });
  } else if (agenda?.length) {
    texto = t('RAMON.CONFERENCIA.DECIDIU_AGENDA', {
      tipo: t(`RAMON.CONFERENCIA.AGENDA.${agenda[0].tipo}`),
      data: dataBr(agenda[0].quando),
    });
  }
  return ultimo
    ? `${texto} · ${t('RAMON.CONFERENCIA.ULTIMO_ANDAMENTO', { data: dataBr(ultimo) })}`
    : texto;
});

const salvar = body => emit('salvar', body);

// Clicar de novo na marca ativa limpa a marcação.
const marcar = m =>
  salvar({ painel_marca: props.linha.painel_marca === m ? null : m });

const salvarObs = e => {
  if (e.target.value !== (props.linha.obs || ''))
    salvar({ obs: e.target.value });
};
</script>

<template>
  <article
    :class="CARTAO"
    class="flex flex-col gap-3 !p-4"
    data-testid="conferencia-linha"
  >
    <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
      <span class="font-semibold text-n-slate-12">{{ linha.cliente }}</span>
      <span class="font-mono text-xs tabular-nums text-n-slate-10">
        {{ linha.numero }}
      </span>
      <span :class="[CHIP, TOM[TOM_DO_GRUPO[linha.grupo]]]">
        {{ t(`RAMON.CONFERENCIA.GRUPO.${linha.grupo}`) }}
      </span>
      <span v-if="linha.responsavel" class="ms-auto text-xs text-n-slate-10">
        {{ linha.responsavel }}
      </span>
    </div>

    <div
      class="grid grid-cols-1 items-center gap-2 md:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)]"
    >
      <template v-for="(lado, i) in lados" :key="lado.chave">
        <span
          v-if="i"
          class="i-lucide-arrow-right size-4 rotate-90 justify-self-center text-n-slate-9 md:rotate-0"
        />
        <div
          class="flex h-full flex-col gap-1.5 rounded-lg bg-n-alpha-1 px-3 py-2"
        >
          <span :class="TITULO">{{
            t(`RAMON.CONFERENCIA.LADO.${lado.chave}`)
          }}</span>
          <span class="text-sm text-n-slate-12">{{ lado.etapa || '—' }}</span>
          <span
            v-if="lado.fase"
            :class="[CHIP, i ? TOM.blue : TOM.slate]"
            class="self-start"
          >
            {{ t(`RAMON.CONFERENCIA.FASE.${lado.fase}`) }}
          </span>
        </div>
      </template>
    </div>

    <p class="m-0 text-xs text-n-slate-11" data-testid="conferencia-decidiu">
      {{ decidiu }}
    </p>

    <div class="flex flex-wrap items-end gap-x-6 gap-y-3">
      <div class="flex items-center gap-2">
        <span class="text-xs text-n-slate-11">
          {{ t('RAMON.CONFERENCIA.PAINEL_CERTO') }}
        </span>
        <div
          class="flex items-center gap-0.5 rounded-lg border border-n-weak p-0.5"
        >
          <button
            v-for="(tom, m) in MARCAS"
            :key="m"
            type="button"
            :data-testid="`conferencia-marca-${m}`"
            :aria-pressed="linha.painel_marca === m"
            :class="[
              CHIP,
              linha.painel_marca === m
                ? TOM[tom]
                : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
            ]"
            @click="marcar(m)"
          >
            {{ t(`RAMON.CONFERENCIA.MARCA.${m}`) }}
          </button>
        </div>
      </div>

      <div v-if="linha.sugestao" class="flex flex-col gap-1">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            type="checkbox"
            class="m-0 accent-n-brand"
            data-testid="conferencia-atualizar"
            :checked="linha.atualizar"
            @change="salvar({ atualizar: $event.target.checked })"
          />
          {{
            t('RAMON.CONFERENCIA.ATUALIZAR', { etapa: linha.sugestao.etapa })
          }}
        </label>
        <p
          v-if="linha.grupo === 'baixa'"
          :class="[AVISO, TOM.amber]"
          class="m-0 !py-1"
        >
          {{ t('RAMON.CONFERENCIA.AVISO_BAIXA') }}
        </p>
      </div>

      <label :class="ROTULO" class="min-w-[12rem] flex-1">
        {{ t('RAMON.CONFERENCIA.OBS') }}
        <input
          type="text"
          data-testid="conferencia-obs"
          :class="CAMPO"
          :value="linha.obs"
          @blur="salvarObs"
        />
      </label>
    </div>

    <div
      v-if="linha.marcado_em || linha.aplicado_em || linha.erro_aplicacao"
      class="flex flex-wrap gap-x-4 gap-y-1 text-xs"
    >
      <span v-if="linha.marcado_em" class="text-n-slate-10">
        {{
          t('RAMON.CONFERENCIA.CONFERIDO_POR', {
            quem: linha.marcado_por,
            ...diaMesHora(linha.marcado_em),
          })
        }}
      </span>
      <span v-if="linha.aplicado_em" class="text-n-teal-11">
        {{
          t('RAMON.CONFERENCIA.APLICADO_POR', {
            quem: linha.aplicado_por,
            ...diaMesHora(linha.aplicado_em),
          })
        }}
      </span>
      <span v-if="linha.erro_aplicacao" class="text-n-ruby-11">
        {{
          t('RAMON.CONFERENCIA.ERRO_APLICACAO', { erro: linha.erro_aplicacao })
        }}
      </span>
    </div>
  </article>
</template>
