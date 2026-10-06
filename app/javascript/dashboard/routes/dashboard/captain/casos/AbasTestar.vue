<script setup>
// Abas do Testar: a conversa avulsa (playground) e os Casos de teste (só admin).
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineProps({
  ativa: { type: String, required: true },
});

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();

const abas = computed(() => {
  const lista = [
    {
      id: 'conversa',
      rota: 'captain_assistants_playground_index',
      label: t('CAPTAIN_RAMON.CASOS.ABA_CONVERSA'),
    },
  ];
  if (isAdmin.value) {
    lista.push({
      id: 'casos',
      rota: 'captain_assistants_casos_teste_index',
      label: t('CAPTAIN_RAMON.CASOS.TITLE'),
    });
  }
  return lista;
});
</script>

<template>
  <nav
    v-if="abas.length > 1"
    data-testid="abas-testar"
    class="flex gap-1 border-b border-n-weak"
  >
    <router-link
      v-for="aba in abas"
      :key="aba.id"
      :to="{ name: aba.rota, params: route.params }"
      :class="[ABA, aba.id === ativa ? ABA_ATIVA : ABA_INATIVA]"
    >
      {{ aba.label }}
    </router-link>
  </nav>
</template>
