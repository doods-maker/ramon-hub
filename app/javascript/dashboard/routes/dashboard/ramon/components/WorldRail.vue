<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SidebarProfileMenu from 'next/sidebar/SidebarProfileMenu.vue';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { uiSettings } = useUISettings();

const isIntranet = computed(() => route.meta?.world === 'intranet');
const shortcuts = computed(() => uiSettings.value.external_shortcuts || []);

const worlds = computed(() => [
  { key: 'conversas', label: t('RAMON.RAIL.CONVERSAS'), icon: 'i-lucide-messages-square', to: accountScopedRoute('home'), active: !isIntranet.value },
  { key: 'intranet', label: t('RAMON.RAIL.INTRANET'), icon: 'i-lucide-layout-dashboard', to: accountScopedRoute('ramon_index'), active: isIntranet.value },
]);
</script>

<template>
  <aside class="flex flex-col items-center flex-shrink-0 h-full py-3 w-[78px] bg-n-background border-r border-n-weak">
    <span class="mb-4 i-lucide-scale size-6 text-n-iris-11" />

    <p class="mb-1 text-[9px] tracking-widest uppercase text-n-slate-9">{{ t('RAMON.RAIL.INTERNOS') }}</p>
    <nav class="flex flex-col items-center w-full gap-1">
      <router-link
        v-for="w in worlds"
        :key="w.key"
        :to="w.to"
        :title="w.label"
        class="flex flex-col items-center justify-center gap-1 rounded-xl w-14 h-14 text-n-slate-11 hover:bg-n-alpha-2"
        :class="{ 'bg-n-alpha-2 text-n-slate-12': w.active }"
      >
        <span :class="w.icon" class="size-5" />
        <span class="text-[9px] leading-none">{{ w.label }}</span>
      </router-link>
    </nav>

    <template v-if="shortcuts.length">
      <p class="mt-4 mb-1 text-[9px] tracking-widest uppercase text-n-slate-9">{{ t('RAMON.RAIL.EXTERNOS') }}</p>
      <nav class="flex flex-col items-center w-full gap-1">
        <a
          v-for="s in shortcuts"
          :key="s.url"
          :href="s.url"
          target="_blank"
          rel="noopener noreferrer"
          :title="s.label"
          class="flex items-center justify-center rounded-xl w-14 h-11 text-n-slate-11 hover:bg-n-alpha-2"
        >
          <span :class="s.icon || 'i-lucide-external-link'" class="size-5" />
        </a>
      </nav>
    </template>

    <router-link
      :to="accountScopedRoute('ramon_external_shortcuts')"
      :title="t('RAMON.RAIL.MANAGE')"
      class="flex items-center justify-center mt-2 rounded-xl w-14 h-9 text-n-slate-9 hover:bg-n-alpha-2 hover:text-n-slate-11"
    >
      <span class="i-lucide-plus size-4" />
    </router-link>

    <div class="mt-auto">
      <SidebarProfileMenu :is-collapsed="true" />
    </div>
  </aside>
</template>
