<script setup>
import { computed, watch } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import LeadsAPI from 'dashboard/api/leads';
import LeadPanelBody from 'dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue';

const emit = defineEmits(['openConversation']);
const store = useStore();
const getters = useStoreGetters();

const { t } = useI18n();
const lead = computed(() => getters['leads/getSelectedLead'].value);

// O índice do Kanban vem slim (sem custom_attributes) — ao abrir a gaveta,
// busca o lead completo pro checklist/colheita/advbox; broadcasts seguem
// atualizando ao vivo por cima.
watch(
  () => lead.value?.id,
  async id => {
    if (!id) return;
    try {
      const { data } = await LeadsAPI.show(id);
      // Resposta atrasada com a gaveta já em outro lead: descarta — o upsert
      // re-injetaria no board um lead que o filtro atual pode ter removido.
      if (getters['leads/getSelectedLead'].value?.id !== id) return;
      store.dispatch('leads/upsert', data);
    } catch (e) {
      useAlert(t('RAMON.FUNIL.DRAWER_LOAD_ERROR'));
    }
  },
  { immediate: true }
);

const close = () => store.dispatch('leads/select', null);

const openConversation = id => {
  emit('openConversation', id);
};

// Esc em pilha: com o dock aberto por cima, o Esc é dele — a gaveta ignora.
onKeyStroke('Escape', () => {
  if (!getters['leads/getDockConversationId'].value) close();
});
</script>

<template>
  <Transition
    enter-active-class="transition duration-150"
    leave-active-class="transition duration-150"
    enter-from-class="opacity-0 translate-x-4"
    leave-to-class="opacity-0 translate-x-4"
  >
    <div v-if="lead" class="fixed inset-0 z-40 flex justify-end">
      <div
        class="absolute inset-0 bg-black/50"
        data-testid="drawer-overlay"
        @click="close"
      />
      <aside
        class="relative z-10 flex flex-col w-96 max-w-full h-full bg-n-solid-1 border-l border-n-weak"
      >
        <button
          data-testid="drawer-close"
          class="absolute top-3 ltr:right-3 rtl:left-3 z-10 text-n-slate-10 hover:text-n-slate-12"
          @click="close"
        >
          <span class="i-lucide-x size-5" />
        </button>

        <!-- corpo compartilhado com o painel da conversa (redesign 1f) -->
        <LeadPanelBody
          :lead="lead"
          context="drawer"
          class="pt-1 [&>div:first-child]:pr-10"
          @open-conversation="openConversation"
          @navigate="close"
        />
      </aside>
    </div>
  </Transition>
</template>
