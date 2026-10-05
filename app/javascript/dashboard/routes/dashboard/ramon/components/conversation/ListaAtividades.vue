<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { formatBrl } from 'dashboard/routes/dashboard/ramon/helpers/currency';
import { TOM } from '../../helpers/ui';

// Linhas da "Atividade recente": cada evento com um ícone colorido pelo tipo,
// quem fez + o quê + quando, e o detalhe embaixo. Usada pelo painel do lead
// (LeadHistory) e pela linha do tempo do Dossiê.
const props = defineProps({
  // mais recente primeiro: { kind, from_value, to_value, author_name, created_at }
  activities: { type: Array, required: true },
  // etapas da conta: a atividade guarda o NOME da etapa (to_value)
  stages: { type: Array, default: () => [] },
  // data e hora (dd/mm/aa hh:mm) em vez do "há 2 dias"
  absoluta: { type: Boolean, default: false },
});
defineOptions({ name: 'ListaAtividades' });

const { t, te } = useI18n();

// kind desconhecido não vaza chave crua (padrão do Dossie)
const label = kind => {
  const key = `RAMON.LEAD_PANEL.HISTORY.KIND.${kind.toUpperCase()}`;
  return te(key) ? t(key) : kind;
};

const etapaPorNome = nome => props.stages.find(s => s.name === nome);

const VISUAL = {
  etapa: { icone: 'i-lucide-arrow-right', tom: TOM.blue },
  ganho: { icone: 'i-lucide-trophy', tom: TOM.teal },
  perda: { icone: 'i-lucide-x', tom: TOM.ruby },
  nota: { icone: 'i-lucide-file-text', tom: TOM.slate },
  campo: { icone: 'i-lucide-plus', tom: TOM.teal },
  dono: { icone: 'i-lucide-user', tom: TOM.iris },
  reuniao: { icone: 'i-lucide-calendar', tom: TOM.amber },
  outro: { icone: 'i-lucide-dot', tom: TOM.slate },
};
const GRUPO = {
  note_added: 'nota',
  created: 'campo',
  value_changed: 'campo',
  thesis_changed: 'campo',
  priority_changed: 'campo',
  lp_recaptured: 'campo',
  sdr_changed: 'dono',
  closer_changed: 'dono',
  meeting_scheduled: 'reuniao',
  meeting_cancelled: 'reuniao',
  reuniao_registrada: 'reuniao',
};
const grupoDe = activity => {
  if (activity.kind !== 'stage_changed') return GRUPO[activity.kind] || 'outro';
  const etapa = etapaPorNome(activity.to_value);
  if (etapa?.is_won) return 'ganho';
  if (etapa?.is_lost) return 'perda';
  return 'etapa';
};

// rótulo do detalhe ("Etapa:", "Valor:"...) por tipo; sem rótulo = só o valor
const DETALHE = {
  stage_changed: 'STAGE',
  value_changed: 'VALUE',
  thesis_changed: 'THESIS',
  priority_changed: 'PRIORITY',
  sdr_changed: 'SDR',
  closer_changed: 'CLOSER',
};

const quando = value => {
  if (!value) return '';
  if (!props.absoluta) return dynamicTime(new Date(value).getTime() / 1000);
  return new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const itens = computed(() =>
  props.activities.map(activity => {
    const grupo = grupoDe(activity);
    const para =
      activity.kind === 'value_changed' && activity.to_value
        ? formatBrl(activity.to_value)
        : activity.to_value;
    return {
      ...activity,
      grupo,
      visual: VISUAL[grupo],
      acao: label(activity.kind),
      quando: quando(activity.created_at),
      rotulo: DETALHE[activity.kind]
        ? t(`RAMON.LEAD_PANEL.HISTORY.DETAIL.${DETALHE[activity.kind]}`)
        : '',
      de: activity.kind === 'stage_changed' ? activity.from_value : null,
      para,
      corPara:
        activity.kind === 'stage_changed'
          ? etapaPorNome(activity.to_value)?.color
          : null,
    };
  })
);
</script>

<template>
  <ul class="mt-1 list-none">
    <li
      v-for="(item, i) in itens"
      :key="item.id ?? i"
      data-testid="activity-row"
      class="flex gap-3 py-2.5 border-t border-n-weak first:border-t-0"
    >
      <span
        data-testid="activity-icon"
        :data-grupo="item.grupo"
        class="flex items-center justify-center size-8 shrink-0 rounded-full"
        :class="item.visual.tom"
      >
        <span class="size-4" :class="item.visual.icone" />
      </span>
      <div class="flex-1 min-w-0">
        <p class="flex items-center gap-1 min-w-0 text-xs">
          <strong class="max-w-[45%] truncate font-semibold text-n-slate-12">
            {{ item.author_name || $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM') }}
          </strong>
          <span class="truncate text-n-slate-10">{{ item.acao }}</span>
          <span
            class="flex items-center gap-0.5 ml-auto shrink-0 text-n-slate-9"
            :class="{ 'font-mono tabular-nums': absoluta }"
          >
            <span class="i-lucide-clock size-3" />
            {{ item.quando }}
          </span>
        </p>
        <p
          v-if="item.para"
          data-testid="activity-detail"
          class="mt-0.5 truncate text-[12.5px] text-n-slate-11"
        >
          <span v-if="item.rotulo">{{ `${item.rotulo}: ` }}</span>
          <template v-if="item.grupo === 'nota'">
            <span class="italic">{{ `“${item.para}”` }}</span>
          </template>
          <template v-else>
            <span v-if="item.de">{{ `${item.de} → ` }}</span>
            <span
              data-testid="activity-para"
              class="font-medium"
              :class="{
                'text-n-iris-11': item.grupo === 'dono',
                'font-mono': item.kind === 'value_changed',
              }"
              :style="item.corPara ? { color: item.corPara } : null"
            >
              {{ item.para }}
            </span>
          </template>
        </p>
      </div>
    </li>
  </ul>
</template>
