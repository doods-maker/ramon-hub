<script setup>
import { useI18n } from 'vue-i18n';
import { brlCompact } from '../../helpers/currency';
import { CARTAO, SECAO, TOM } from '../../helpers/ui';

// "Semana · time" (mock 1b): ranking por agente + NPS da semana como rodapé.
defineProps({
  team: { type: Array, default: () => [] },
  nps: { type: Object, default: null },
});

const { t } = useI18n();

const initials = name =>
  (name || '')
    .split(' ')
    .map(word => word[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();

const npsMedia = media =>
  new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(Number(media) || 0);
</script>

<template>
  <div data-testid="team-week" :class="CARTAO" class="flex flex-col gap-2">
    <div
      v-for="row in team"
      :key="row.user_id"
      data-testid="team-row"
      class="flex items-center gap-2.5"
    >
      <img
        v-if="row.avatar_url"
        :src="row.avatar_url"
        :alt="row.name"
        class="flex-none rounded-full size-[26px] object-cover"
      />
      <span
        v-else
        class="flex items-center justify-center flex-none rounded-full size-[26px] text-[10px] font-semibold"
        :class="TOM.blue"
      >
        {{ initials(row.name) }}
      </span>
      <span class="text-[13px] truncate text-n-slate-12">{{ row.name }}</span>
      <span
        class="ml-auto font-mono text-xs whitespace-nowrap"
        :class="row.won_count ? 'text-n-teal-11' : 'text-n-slate-9'"
      >
        <template v-if="row.won_count">
          {{
            t('RAMON.COMMAND.TEAM.WON', {
              count: row.won_count,
              value: brlCompact(row.won_value),
            })
          }}
        </template>
        <template v-else>—</template>
      </span>
      <span class="text-xs tabular-nums whitespace-nowrap text-n-slate-10">
        {{ t('RAMON.COMMAND.TEAM.ACTIONS', { count: row.activities_count }) }}
      </span>
    </div>
    <p v-if="!team.length" class="text-xs text-n-slate-10">
      {{ t('RAMON.COMMAND.TEAM.EMPTY') }}
    </p>
    <p
      v-if="nps && nps.respostas > 0"
      data-testid="team-nps"
      :class="SECAO"
      class="mt-1 text-[11px] text-n-slate-10"
    >
      {{
        t('RAMON.COMMAND.TEAM.NPS_LINE', {
          media: npsMedia(nps.media),
          count: nps.respostas,
        })
      }}
    </p>
  </div>
</template>
