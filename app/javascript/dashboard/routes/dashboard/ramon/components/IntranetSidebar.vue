<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

// `names` = rotas que acendem o item (deep-links contextuais acendem o irmão:
// ex. Cálculos por lead acende "Cálculos"). `adminOnly` espelha o guard da rota.
const sections = computed(() =>
  [
    {
      label: t('RAMON.NAV.COMERCIAL'),
      items: [
        {
          key: 'overview',
          label: t('RAMON.NAV.OVERVIEW'),
          icon: 'i-lucide-layout-dashboard',
          to: accountScopedRoute('ramon_index'),
          names: ['ramon_index'],
        },
        {
          key: 'esteira',
          label: t('RAMON.NAV.ESTEIRA'),
          icon: 'i-lucide-zap',
          to: accountScopedRoute('ramon_esteira'),
          names: ['ramon_esteira'],
        },
        {
          key: 'funil',
          label: t('RAMON.NAV.FUNIL'),
          icon: 'i-lucide-filter',
          to: accountScopedRoute('ramon_funil'),
          names: ['ramon_funil'],
        },
        {
          key: 'agenda',
          label: t('RAMON.NAV.AGENDA'),
          icon: 'i-lucide-calendar-days',
          to: accountScopedRoute('ramon_agenda'),
          names: ['ramon_agenda'],
        },
        {
          key: 'pessoas',
          label: t('RAMON.NAV.LINHA_DA_VIDA'),
          icon: 'i-lucide-heart-pulse',
          to: accountScopedRoute('ramon_pessoas'),
          names: ['ramon_pessoas', 'ramon_linha_da_vida', 'ramon_lead_dossie'],
        },
        {
          key: 'calculos',
          label: t('RAMON.NAV.CALCULOS'),
          icon: 'i-lucide-calculator',
          to: accountScopedRoute('ramon_calculos'),
          names: ['ramon_calculos', 'ramon_calculos_lead'],
        },
        {
          key: 'funil_config',
          label: t('RAMON.NAV.FUNIL_CONFIG'),
          icon: 'i-lucide-sliders-horizontal',
          to: accountScopedRoute('ramon_funil_config'),
          names: ['ramon_funil_config'],
          adminOnly: true,
        },
        {
          key: 'playbooks',
          label: t('RAMON.NAV.PLAYBOOKS'),
          icon: 'i-lucide-book-open',
          to: accountScopedRoute('ramon_playbooks'),
          names: ['ramon_playbooks'],
          adminOnly: true,
        },
        {
          key: 'sdr',
          label: t('RAMON.NAV.SDR'),
          icon: 'i-lucide-phone',
          soon: true,
        },
      ],
    },
    {
      label: t('RAMON.NAV.JURIDICO'),
      items: [
        {
          key: 'triagem',
          label: t('RAMON.NAV.TRIAGEM'),
          icon: 'i-lucide-gavel',
          soon: true,
        },
      ],
    },
    {
      label: t('RAMON.NAV.INTELIGENCIA'),
      items: [
        {
          key: 'agentes',
          label: t('RAMON.NAV.AGENTES'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('ramon_triage_agents'),
          names: ['ramon_triage_agents'],
          adminOnly: true,
        },
      ],
    },
  ]
    .map(section => ({
      ...section,
      items: section.items.filter(item => !item.adminOnly || isAdmin.value),
    }))
    .filter(section => section.items.length)
);

const isActive = item => item.names?.includes(route.name);
</script>

<template>
  <aside
    class="flex flex-col flex-shrink-0 w-[220px] h-full py-3 overflow-y-auto bg-n-solid-1 border-r border-n-weak"
  >
    <h2 class="px-4 mb-4 text-xl font-cormorant text-n-slate-12">
      {{ t('RAMON.NAV.TITLE') }}
    </h2>
    <template v-for="section in sections" :key="section.label">
      <p
        class="px-4 pt-3 pb-1 text-[10px] tracking-widest uppercase text-n-slate-9"
      >
        {{ section.label }}
      </p>
      <nav class="flex flex-col gap-0.5 px-2">
        <component
          :is="item.soon ? 'div' : 'router-link'"
          v-for="item in section.items"
          :key="item.key"
          :to="item.soon ? undefined : item.to"
          :title="item.label"
          class="flex items-center h-8 gap-2 px-2 text-sm rounded-lg"
          :class="[
            item.soon ? 'text-n-slate-9 cursor-default' : 'hover:bg-n-alpha-2',
            !item.soon && isActive(item)
              ? 'bg-n-alpha-2 text-n-iris-11'
              : !item.soon && 'text-n-slate-11 hover:text-n-slate-12',
          ]"
        >
          <span :class="item.icon" class="flex-shrink-0 size-4" />
          <span class="truncate">{{ item.label }}</span>
          <span
            v-if="item.soon"
            class="ml-auto text-[9px] uppercase text-n-slate-9"
            >{{ t('RAMON.NAV.SOON') }}</span
          >
        </component>
      </nav>
    </template>
  </aside>
</template>
