<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';

import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { ROTAS_DAS_FAQS, assistenteDasFaqs } from './assistenteDasFaqs';

const store = useStore();
const router = useRouter();
const { uiSettings } = useUISettings();
const route = useRoute();

const assistants = computed(
  () => store.getters['captainAssistants/getRecords']
);

const daFaq = ref(null);

const isAssistantPresent = assistantId => {
  return !!assistants.value.find(a => a.id === Number(assistantId));
};

const routeToView = (name, params) => {
  router.replace({ name, params, replace: true });
};

const generateRouterParams = () => {
  // I-FQ5: FAQs e Documentos abrem sempre no assistente que fala com o lead.
  if (daFaq.value) return { assistantId: daFaq.value };

  const { last_active_assistant_id: lastActiveAssistantId } =
    uiSettings.value || {};

  if (isAssistantPresent(lastActiveAssistantId)) {
    return {
      assistantId: lastActiveAssistantId,
    };
  }

  if (assistants.value.length > 0) {
    const { id: assistantId } = assistants.value[0];
    return { assistantId };
  }

  return null;
};

// Rota de destino; caminho ausente/inválido cai nas FAQs (F7: o assistente das FAQs vale também aí).
const rotaFinal = () => {
  const { navigationPath } = route.params;
  return [
    ...ROTAS_DAS_FAQS, // Faq page, Document page
    'captain_assistants_scenarios_index', // Scenario page
    'captain_assistants_playground_index', // Playground page
    'captain_assistants_inboxes_index', // Inboxes page
    'captain_tools_index', // Tools page
    'captain_assistants_settings_index', // Settings page
  ].includes(navigationPath)
    ? navigationPath
    : 'captain_assistants_responses_index';
};

const routeToLastActiveAssistant = () => {
  const params = generateRouterParams();

  // No assistants found, redirect to create page
  if (!params) {
    return routeToView('captain_assistants_create_index', {
      accountId: route.params.accountId,
    });
  }

  return routeToView(rotaFinal(), {
    accountId: route.params.accountId,
    ...params,
  });
};

const performRouting = async () => {
  await store.dispatch('captainAssistants/get');
  if (ROTAS_DAS_FAQS.includes(rotaFinal())) {
    try {
      const { data } = await CaptainAssistantAPI.stats();
      daFaq.value = assistenteDasFaqs(data.payload)?.id ?? null;
    } catch (e) {
      daFaq.value = null;
    }
  }
  nextTick(() => routeToLastActiveAssistant());
};

onMounted(() => performRouting());
</script>

<template>
  <div
    class="flex items-center justify-center w-full bg-n-surface-1 text-n-slate-11"
  >
    <Spinner />
  </div>
</template>
