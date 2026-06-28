<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const sections = computed(() => [
  {
    label: t('RAMON.NAV.COMERCIAL'),
    items: [
      { key: 'overview', label: t('RAMON.NAV.OVERVIEW'), icon: 'i-lucide-layout-dashboard', to: accountScopedRoute('ramon_index') },
      { key: 'funil', label: t('RAMON.NAV.FUNIL'), icon: 'i-lucide-filter', to: accountScopedRoute('ramon_funil') },
      { key: 'sdr', label: t('RAMON.NAV.SDR'), icon: 'i-lucide-phone', soon: true },
    ],
  },
  {
    label: t('RAMON.NAV.JURIDICO'),
    items: [{ key: 'triagem', label: t('RAMON.NAV.TRIAGEM'), icon: 'i-lucide-gavel', soon: true }],
  },
  {
    label: t('RAMON.NAV.INTELIGENCIA'),
    items: [{ key: 'agentes', label: t('RAMON.NAV.AGENTES'), icon: 'i-lucide-bot', soon: true }],
  },
]);
</script>

<template>
  <aside class="flex flex-col flex-shrink-0 w-[220px] h-full py-3 overflow-y-auto bg-n-solid-1 border-r border-n-weak">
    <h2 class="px-4 mb-4 text-xl font-cormorant text-n-slate-12">{{ t('RAMON.NAV.TITLE') }}</h2>
    <template v-for="section in sections" :key="section.label">
      <p class="px-4 pt-3 pb-1 text-[10px] tracking-widest uppercase text-n-slate-9">{{ section.label }}</p>
      <nav class="flex flex-col gap-0.5 px-2">
        <component
          :is="item.soon ? 'div' : 'router-link'"
          v-for="item in section.items"
          :key="item.key"
          :to="item.soon ? undefined : item.to"
          :title="item.label"
          class="flex items-center h-8 gap-2 px-2 text-sm rounded-lg"
          :class="item.soon ? 'text-n-slate-9 cursor-default' : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'"
        >
          <span :class="item.icon" class="flex-shrink-0 size-4" />
          <span class="truncate">{{ item.label }}</span>
          <span v-if="item.soon" class="ml-auto text-[9px] uppercase text-n-slate-9">{{ t('RAMON.NAV.SOON') }}</span>
        </component>
      </nav>
    </template>
  </aside>
</template>
