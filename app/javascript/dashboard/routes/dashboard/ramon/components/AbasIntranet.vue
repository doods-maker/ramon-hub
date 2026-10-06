<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { grupoDaRota } from '../helpers/navIntranet';
import { ABA, ABA_ATIVA, ABA_INATIVA } from '../helpers/ui';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

// Faixa de abas do item do menu: só quando o grupo tem 2+ abas visíveis.
const abas = computed(() => {
  const lista = grupoDaRota(route.name, isAdmin.value)?.abas || [];
  return lista.length > 1 ? lista : [];
});
</script>

<template>
  <!-- Fundo sólido + borda: navegação da página, não se confunde com as abas
       internas das telas (Agenda, simulador), que ficam no fundo da página. -->
  <nav
    v-if="abas.length"
    class="flex flex-shrink-0 gap-1 overflow-x-auto border-b border-n-weak bg-n-solid-1 px-4 sm:px-8"
  >
    <router-link
      v-for="aba in abas"
      :key="aba.name"
      :to="accountScopedRoute(aba.name)"
      :class="[ABA, aba.names.includes(route.name) ? ABA_ATIVA : ABA_INATIVA]"
    >
      {{ t(aba.label) }}
    </router-link>
  </nav>
</template>
