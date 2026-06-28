<script setup>
import { useI18n } from 'vue-i18n';
const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background p-8">
    <header class="mb-8">
      <p class="text-xs tracking-[0.2em] uppercase text-n-slate-11">
        {{ t('RAMON.OVERVIEW.EYEBROW') }}
      </p>
      <h1 class="font-cormorant text-4xl font-semibold text-n-slate-12">
        {{ t('RAMON.OVERVIEW.TITLE') }}
      </h1>
    </header>
    <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
      <div
        v-for="kpi in ['LEADS', 'REUNIOES', 'FECHAMENTOS']"
        :key="kpi"
        class="p-6 border rounded-xl border-n-weak bg-n-solid-2"
      >
        <p class="text-xs tracking-wide uppercase text-n-slate-11">
          {{ t(`RAMON.OVERVIEW.KPI.${kpi}`) }}
        </p>
        <p class="mt-2 font-cormorant text-3xl text-n-slate-12">—</p>
      </div>
    </div>
    <p class="mt-8 text-sm text-n-slate-11">
      {{ t('RAMON.OVERVIEW.PLACEHOLDER') }}
    </p>
  </div>
</template>
