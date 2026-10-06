<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { secoesIntranet } from '../helpers/navIntranet';

defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['closeMobileSidebar']);

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

// Grupos e abas: helpers/navIntranet.js. O item leva à 1ª aba visível e
// acende em qualquer rota das suas abas.
const sections = computed(() => secoesIntranet(isAdmin.value));

const isActive = grupo => grupo.abas.some(a => a.names.includes(route.name));
</script>

<template>
  <!-- Backdrop mobile: toque fecha o drawer (desktop = sem backdrop) -->
  <div
    v-if="isMobileSidebarOpen"
    class="fixed inset-0 z-30 bg-black/40 md:hidden"
    @click="emit('closeMobileSidebar')"
  />
  <aside
    class="flex flex-col w-[220px] h-full py-3 overflow-y-auto bg-n-solid-1 border-r border-n-weak fixed top-0 ltr:left-0 rtl:right-0 z-40 md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 transition-transform duration-200 ease-out"
    :class="{
      'shadow-lg md:shadow-none': isMobileSidebarOpen,
      'ltr:-translate-x-full rtl:translate-x-full md:translate-x-0':
        !isMobileSidebarOpen,
    }"
  >
    <h2 class="px-4 mb-4 text-xl font-semibold text-n-slate-12">
      {{ t('RAMON.NAV.TITLE') }}
    </h2>
    <!-- Mobile: a rail de mundos fica oculta — atalho pro outro mundo aqui -->
    <router-link
      :to="accountScopedRoute('home')"
      class="md:hidden flex items-center gap-2 mx-2 mb-3 px-2 py-1.5 text-sm rounded-lg text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
      @click="emit('closeMobileSidebar')"
    >
      <span class="i-lucide-messages-square size-4" />
      {{ t('RAMON.RAIL.CONVERSAS') }}
    </router-link>
    <template v-for="section in sections" :key="section.label">
      <p
        class="px-4 pt-3 pb-1 text-[10px] tracking-widest uppercase text-n-slate-9"
      >
        {{ t(section.label) }}
      </p>
      <nav class="flex flex-col gap-0.5 px-2">
        <router-link
          v-for="grupo in section.grupos"
          :key="grupo.key"
          :to="accountScopedRoute(grupo.abas[0].name)"
          :title="t(grupo.label)"
          class="flex items-center h-8 gap-2 px-2 text-sm rounded-lg hover:bg-n-alpha-2"
          :class="
            isActive(grupo)
              ? 'bg-n-alpha-2 text-n-iris-11'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
        >
          <span :class="grupo.icon" class="flex-shrink-0 size-4" />
          <span class="truncate">{{ t(grupo.label) }}</span>
        </router-link>
      </nav>
    </template>
  </aside>
</template>
